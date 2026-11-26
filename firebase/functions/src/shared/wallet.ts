/**
 * Wallet session inside a Firestore transaction: load once, apply debits/credits (each one
 * produces a ledger entry), write once. Balance can never go negative.
 */
import { createHmac, timingSafeEqual } from 'node:crypto';
import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { fail } from './errors';
import { refs } from './paths';
import { walletSigningKey } from './secrets';
import type { LedgerEntryDoc, LedgerType, PaymentMethod, PowerId, WalletDoc } from './types';

/**
 * HMAC over the money-bearing fields and the uid. Binding the uid prevents copying another
 * account's (validly signed) wallet onto your own. The key comes from the Functions runtime only,
 * so a client with direct database access cannot produce a matching signature for a value it made up.
 */
export function walletSignature(uid: string, doc: Pick<WalletDoc, 'balanceCents' | 'totalDepositedCents' | 'totalWithdrawnCents'>): string {
  const canonical = `v1|${uid}|${doc.balanceCents}|${doc.totalDepositedCents}|${doc.totalWithdrawnCents}`;
  return createHmac('sha256', walletSigningKey()).update(canonical).digest('hex');
}

function signatureValid(uid: string, doc: WalletDoc): boolean {
  const expected = walletSignature(uid, doc);
  const got = doc.sig ?? '';
  if (got.length !== expected.length) return false;
  try {
    return timingSafeEqual(Buffer.from(got), Buffer.from(expected));
  } catch {
    return false;
  }
}

export interface LedgerRef {
  tableId?: string | null;
  handNumber?: number | null;
  marketId?: string | null;
  powerId?: PowerId | null;
  method?: PaymentMethod | null;
}

export class WalletSession {
  private entries: LedgerEntryDoc[] = [];
  private constructor(
    private readonly db: Firestore,
    readonly uid: string,
    readonly doc: WalletDoc,
    private readonly now: number,
  ) {}

  /** Reads the wallet (must happen before any write of the transaction). PROFILE_REQUIRED if missing. */
  static async load(db: Firestore, tx: Transaction, uid: string, now: number): Promise<WalletSession> {
    const snap = await tx.get(refs(db).wallet(uid));
    if (!snap.exists) throw fail.pre('PROFILE_REQUIRED', 'no wallet');
    const doc = snap.data() as WalletDoc;
    // Reject any wallet whose balance was changed outside the callables (no valid signature):
    // the forged money is never spendable. Legacy wallets must be backfilled (src/sim/signWallets.ts).
    if (!signatureValid(uid, doc)) throw fail.pre('WALLET_INTEGRITY', 'wallet signature invalid');
    return new WalletSession(db, uid, doc, now);
  }

  /** New wallet for a freshly created profile. */
  static create(db: Firestore, uid: string, now: number): WalletSession {
    return new WalletSession(db, uid, {
      balanceCents: 0, totalDepositedCents: 0, totalWithdrawnCents: 0,
      dailyDeposit: { day: '', amountCents: 0 }, updatedAtMs: now,
    }, now);
  }

  get balance(): number {
    return this.doc.balanceCents;
  }

  get changed(): boolean {
    return this.entries.length > 0;
  }

  canAfford(cents: number): boolean {
    return cents <= this.doc.balanceCents;
  }

  debit(cents: number, type: LedgerType, ref: LedgerRef = {}): string {
    if (!Number.isSafeInteger(cents) || cents < 0) throw fail.invalid('INVALID_ARGUMENT', 'bad debit');
    if (cents === 0) return '';
    if (cents > this.doc.balanceCents) throw fail.pre('INSUFFICIENT_FUNDS');
    return this.push(-cents, type, ref);
  }

  credit(cents: number, type: LedgerType, ref: LedgerRef = {}): string {
    if (!Number.isSafeInteger(cents) || cents < 0) throw fail.invalid('INVALID_ARGUMENT', 'bad credit');
    if (cents === 0) return '';
    return this.push(cents, type, ref);
  }

  private push(amount: number, type: LedgerType, ref: LedgerRef): string {
    this.doc.balanceCents += amount;
    const id = refs(this.db).ledger(this.uid).doc().id;
    this.entries.push({
      entryId: id, type, amountCents: amount, balanceAfterCents: this.doc.balanceCents, createdAtMs: this.now,
      tableId: ref.tableId ?? null, handNumber: ref.handNumber ?? null, marketId: ref.marketId ?? null,
      powerId: ref.powerId ?? null, method: ref.method ?? null,
    });
    return id;
  }

  /** Writes the wallet and the ledger entries (call after all reads of the transaction). */
  write(tx: Transaction): void {
    if (!this.changed) return;
    this.doc.updatedAtMs = this.now;
    this.doc.sig = walletSignature(this.uid, this.doc); // re-sign after every balance change
    tx.set(refs(this.db).wallet(this.uid), this.doc);
    for (const e of this.entries) tx.set(refs(this.db).ledger(this.uid).doc(e.entryId), e);
    this.entries = [];
  }
}
