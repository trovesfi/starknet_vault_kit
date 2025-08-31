// Configurable values
const MAX_APY = 100;       // in %
const MAX_SPEND_PER_DAY = 160; // in USD
const TVL_VALUES = [50000, 100000, 250000, 500000, 1000000];

// Function to compute spend per day and APY
function computeYield(tvl) {
  // Spend required to reach MAX_APY
  const spendForMaxAPY = (tvl * MAX_APY) / (365 * 100);

  // Actual spend per day = min(spendForMaxAPY, MAX_SPEND_PER_DAY)
  const spendPerDay = Math.min(spendForMaxAPY, MAX_SPEND_PER_DAY);

  // Compute APY based on actual spend
  const apy = (spendPerDay * 365 * 100) / tvl;

  return { tvl, spendPerDay, apy };
}

// Generate results
const results = TVL_VALUES.map(computeYield);

// Print as table
console.log(" TVL ($)   | Spend/Day ($) | APY (%) ");
console.log("-------------------------------------");
results.forEach(({ tvl, spendPerDay, apy }) => {
  console.log(
    `${tvl.toString().padStart(8)} | ${spendPerDay.toFixed(2).padStart(12)} | ${apy.toFixed(2).padStart(7)}`
  );
});
