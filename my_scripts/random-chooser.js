// Hardcoded weights for 10 items (random between 1–5)
const weights = [1, 5, 3, 2, 4, 1, 5, 2, 3, 4]; 
const totalWeight = weights.reduce((a, b) => a + b, 0);

function weightedRandomPick(weights) {
  const r = Math.random() * totalWeight;
  let cum = 0;
  for (let i = 0; i < weights.length; i++) {
    cum += weights[i];
    if (r < cum) return i;
  }
}

// Run 100 random picks
const nRuns = 1000;
const counts = Array(weights.length).fill(0);

for (let i = 0; i < nRuns; i++) {
  const pick = weightedRandomPick(weights);
  counts[pick]++;
}

// Print results
console.log("Item | Weight | ExpectedProb | ActualProb");
console.log("------------------------------------------");
for (let i = 0; i < weights.length; i++) {
  const expected = (weights[i] / totalWeight).toFixed(3);
  const actual = (counts[i] / nRuns).toFixed(3);
  console.log(`${i+1}    | ${weights[i]}      | ${expected}        | ${actual}`);
}
