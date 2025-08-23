export interface Strategy {
  vault: string;
  startBlockIndexing: number;
}

export interface PendingRedeem {
  epoch: number;
  sharesBurn: string;
  nominal: string;
  assets: string;
  redeemId: string;
  timestamp: number;
  transactionHash: string;
}