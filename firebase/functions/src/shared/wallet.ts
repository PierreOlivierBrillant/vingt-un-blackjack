/**
 * Wallet session inside a Firestore transaction: load once, apply debits/credits (each one
 * produces a ledger entry), write once. Balance can never go negative.
 */
import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { fail } from './errors';
import { refs } from './paths';
import type { LedgerEntryDoc, LedgerType, PaymentMethod, PowerId, WalletDoc } from './types';

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
    return new WalletSession(db, uid, snap.data() as WalletDoc, now);
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
    tx.set(refs(this.db).wallet(this.uid), this.doc);
    for (const e of this.entries) tx.set(refs(this.db).ledger(this.uid).doc(e.entryId), e);
    this.entries = [];
  }
}
