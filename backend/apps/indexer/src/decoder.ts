// Convert u256 from two field elements
export function parseU256(data: string[]): bigint {
  const low = BigInt(data[0]);
  const high = BigInt(data[1]);
  return (high << 128n) | low;
}

// Parse a u64 (1 felt)
export function parseFelt(felt: string): bigint {
  return BigInt(felt);
}

export function decodeRedeemRequestedEvent(rawData: string[]) {
  let i = 0;
  const owner = parseFelt(rawData[i++]);
  const receiver = parseFelt(rawData[i++]);
  const shares = parseU256([rawData[i++], rawData[i++]]);
  const assets = parseU256([rawData[i++], rawData[i++]]);
  const redeemId = parseU256([rawData[i++], rawData[i++]]);
  const epoch = parseU256([rawData[i++], rawData[i++]]);

  return {
    owner,
    receiver,
    shares,
    assets,
    redeemId,
    epoch,
  };
}

export function decodeRedeemClaimedEvent(rawData: string[]) {
  let i = 0;

  // Parse ContractAddress value as bigint
  const receiver = parseFelt(rawData[i++]);

  // Parse u256 values (each takes two array elements)
  const redeemRequestNominal = parseU256([rawData[i++], rawData[i++]]);
  const assets = parseU256([rawData[i++], rawData[i++]]);
  const redeemId = parseU256([rawData[i++], rawData[i++]]);
  const epoch = parseU256([rawData[i++], rawData[i++]]);

  return {
    receiver,
    redeemRequestNominal,
    assets,
    redeemId,
    epoch,
  };
}

export function decodeReportEvent(rawData: string[]) {
  let i = 0;
  const newEpoch = parseU256([rawData[i++], rawData[i++]]);
  const newHandledEpochLen = parseU256([rawData[i++], rawData[i++]]);
  const totalSupply = parseU256([rawData[i++], rawData[i++]]);
  const totalAssets = parseU256([rawData[i++], rawData[i++]]);
  const managementFeeShares = parseU256([rawData[i++], rawData[i++]]);
  const performanceFeeShares = parseU256([rawData[i++], rawData[i++]]);
  return {
    newEpoch,
    newHandledEpochLen,
    totalSupply,
    totalAssets,
    managementFeeShares,
    performanceFeeShares,
  };
}