
/** Learnings: 
 * Logic wont work without previous estimated apy values */

function simulateAUM({
  hours = 24 * 14, // simulate 2 weeks
  rewardRatePerHour = 0.000114, // ~10% APY
  harvestInterval = 24 * 7
}) {
  let prevAUM = 100; // starting AUM
  let currentAssets = 100; // starting assets

  let estimatedReward = 0;
  let pendingDeposit = 0;
  let pendingWithdrawal = 0;

  for (let t = 1; t <= hours; t++) {
    // === Random deposits/withdrawals simulation ===
    if (Math.random() < 0.1) { // 10% chance deposit
      const dep = Math.floor(Math.random() * 20) + 5; 
      pendingDeposit += dep;
      console.log(`[t=${t}] New deposit queued: ${dep}`);
    }
    if (Math.random() < 0.05) { // 5% chance withdrawal
      const wd = Math.floor(Math.random() * 15) + 5; 
      pendingWithdrawal += wd;
      console.log(`[t=${t}] New withdrawal requested: ${wd}`);
    }

    // === Process withdrawals immediately ===
    if (pendingWithdrawal > 0) {
      if (currentAssets >= pendingWithdrawal) {
        currentAssets -= pendingWithdrawal;
        prevAUM -= pendingWithdrawal; 
        console.log(`[t=${t}] Withdrawal fulfilled: ${pendingWithdrawal}`);
        pendingWithdrawal = 0;
      } else {
        throw new Error(`Withdrawal exceeded assets: ${pendingWithdrawal}`);
      }
    }

    // === AUM growth from rewards ===
    estimatedReward += prevAUM * rewardRatePerHour;
    let realisedReward = 0;

    let contractAUM = currentAssets + estimatedReward;

    // === Realise rewards on harvest ===
    if (t % harvestInterval === 0) {
      realisedReward = 2; // fixed rewards
      currentAssets += realisedReward;
      prevAUM = currentAssets;
      estimatedReward = 0;
      console.log(`[t=${t}] HARVEST: realised=${realisedReward.toFixed(2)}, new assets=${currentAssets.toFixed(2)}`);
    } else {
      prevAUM = contractAUM;
    }

    // === Process deposits (only after reporting step, delayed effect) ===
    if (pendingDeposit > 0) {
      currentAssets += pendingDeposit;
      prevAUM += pendingDeposit; // grows only from next reporting cycle
      console.log(`[t=${t}] Deposit added: ${pendingDeposit}`);
      pendingDeposit = 0;
    }

    // === Reporting log ===
    console.log(
      `[t=${t}] AUM=${prevAUM.toFixed(2)}, Assets=${currentAssets.toFixed(2)}, estReward=${estimatedReward.toFixed(2)}, realisedReward=${realisedReward.toFixed(2)}`
    );
  }
}

simulateAUM({});
