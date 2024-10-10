export interface IDLTPermit {
  owner: string; 
  spender: string; 
  mainId: bigint;
  subId: bigint;
  amount: bigint; 
  deadline: bigint; 
  nonce: bigint;
}
