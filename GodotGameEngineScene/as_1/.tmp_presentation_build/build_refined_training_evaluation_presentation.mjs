import fs from "fs";
import path from "path";
import { Presentation, PresentationFile } from "@oai/artifact-tool";

const ROOT = "/Users/booxuan/Documents/as_1";
const OUT = path.join(ROOT, "AS1_PPO_Training_and_Evaluation_Refined_Presentation.pptx");
const RENDER_DIR = path.join(ROOT, ".tmp_presentation_build", "refined_rendered");

const C = {
  white: "#FFFFFF", ink: "#15171A", muted: "#5B6470", pale: "#F2F4F6",
  rule: "#C7CDD4", blue: "#3D8DFF", sky: "#6DCBF4", bluePale: "#EAF5FB",
  dark: "#182333", green: "#31814B", red: "#C74634", amber: "#C78511",
};

function imageBytes(relativePath) {
  return fs.readFileSync(path.join(ROOT, relativePath));
}

function readCsv(relativePath) {
  const [header, ...rows] = fs.readFileSync(path.join(ROOT, relativePath), "utf8").trim().split(/\r?\n/);
  const columns = header.split(",");
  return rows.map((row) => Object.fromEntries(columns.map((column, index) => [column, row.split(",")[index] ?? ""])));
}

function addShape(slide, x, y, width, height, opts = {}) {
  return slide.shapes.add({
    geometry: opts.geometry ?? "rect",
    position: { left: x, top: y, width, height },
    fill: opts.fill ?? C.white,
    line: opts.line ?? { style: "solid", width: 0, fill: opts.fill ?? C.white },
  });
}

function addText(slide, text, x, y, width, height, opts = {}) {
  const box = slide.shapes.add({
    geometry: "textbox",
    position: { left: x, top: y, width, height },
    fill: "none",
    line: { style: "solid", width: 0, fill: "none" },
  });
  box.text = text;
  box.text.style = {
    fontSize: opts.size ?? 18,
    bold: opts.bold ?? false,
    color: opts.color ?? C.ink,
    alignment: opts.align ?? "left",
    verticalAlignment: opts.valign ?? "top",
    autoFit: "shrinkText",
  };
  return box;
}

function addImage(slide, relativePath, x, y, width, height, alt) {
  return slide.images.add({
    data: imageBytes(relativePath),
    position: { left: x, top: y, width, height },
    fit: "contain",
    alt,
  });
}

function addNotes(slide, sources) {
  slide.speakerNotes.textFrame.setText(`[Sources]\n${sources.map((source) => `- ${source}`).join("\n")}`);
}

function addBase(slide, number, kicker, title) {
  slide.background.fill = C.white;
  addShape(slide, 0, 0, 1280, 12, { fill: C.blue });
  addText(slide, kicker.toUpperCase(), 42, 34, 1000, 22, { size: 13, bold: true, color: C.blue });
  addText(slide, title, 40, 68, 1188, 78, { size: 36, bold: true });
  addShape(slide, 40, 660, 1198, 1, { fill: C.rule });
  addText(slide, "UCCD2063 • PPO training and evaluation", 40, 674, 580, 18, { size: 11, color: C.muted });
  addText(slide, String(number).padStart(2, "0"), 1180, 670, 58, 20, { size: 12, bold: true, color: C.muted, align: "right" });
}

function addMetric(slide, x, y, width, value, label, accent = C.blue) {
  addShape(slide, x, y, width, 96, { geometry: "roundRect", fill: C.pale, line: { style: "solid", width: 1, fill: C.rule } });
  addShape(slide, x, y, 6, 96, { geometry: "roundRect", fill: accent, line: { style: "solid", width: 0, fill: accent } });
  addText(slide, value, x + 22, y + 16, width - 36, 35, { size: 27, bold: true });
  addText(slide, label, x + 22, y + 58, width - 36, 24, { size: 15, color: C.muted });
}

function addTable(slide, values, x, y, width, height, columnWidths, emphasisRows = []) {
  const table = slide.tables.add({ rows: values.length, columns: values[0].length, left: x, top: y, width, height, values, columnWidths });
  table.styleOptions = { headerRow: true, bandedRows: true };
  table.borders.assign({ style: "solid", fill: C.rule, width: 1 });
  table.cells.block({ row: 0, column: 0, rowCount: 1, columnCount: values[0].length }).assign({
    fill: C.dark,
    textStyle: { bold: true, color: C.white, fontSize: 15 },
  });
  table.cells.block({ row: 1, column: 0, rowCount: values.length - 1, columnCount: values[0].length }).assign({
    textStyle: { color: C.ink, fontSize: 15 },
  });
  for (const row of emphasisRows) {
    table.cells.block({ row, column: 0, rowCount: 1, columnCount: values[0].length }).assign({
      fill: C.bluePale,
      textStyle: { bold: true, color: C.ink, fontSize: 15 },
    });
  }
  return table;
}

function addBarChart(slide, x, y, width, height, categories, values, opts = {}) {
  slide.charts.add("bar", {
    position: { left: x, top: y, width, height },
    categories,
    series: [{ name: opts.seriesName ?? "Value", values, fill: opts.fill ?? C.blue }],
    hasLegend: false,
    barOptions: { direction: "bar", grouping: "clustered", gapWidth: 38 },
    dataLabels: { showValue: true, position: "outEnd", textStyle: { fill: C.ink, fontSize: 12, bold: true } },
    chartFill: C.white,
    chartLine: { style: "solid", width: 0, fill: C.white },
    plotAreaFill: C.white,
    plotAreaLine: { style: "solid", width: 0, fill: C.white },
    xAxis: { min: opts.min, max: opts.max, majorUnit: opts.majorUnit, textStyle: { fill: C.muted, fontSize: 11 }, majorGridlines: { style: "solid", width: 1, fill: C.rule } },
    yAxis: { textStyle: { fill: C.ink, fontSize: 12 }, line: { style: "solid", width: 0, fill: C.white } },
  });
}

function pct(value) { return `${Math.round(Number(value) * 100)}%`; }
function f2(value) { return Number(value).toFixed(2); }

const plan = readCsv("results/experiment_plan.csv");
const deterministic = readCsv("results/all_experiment_summaries.csv");
const stochastic = readCsv("results/all_stochastic_experiment_summaries.csv");
const training = readCsv("results/all_training_metadata.csv");
const policy = readCsv("results/policy_comparison.csv");
const seedMatrix = readCsv("results/seed_matrix_summary.csv");
const byName = (rows) => new Map(rows.map((row) => [row.name, row]));
const deterministicByName = byName(deterministic);
const stochasticByName = byName(stochastic);
const trainingByName = byName(training);
const seedsByName = byName(seedMatrix);
const shortName = {
  baseline: "Baseline", low_lr: "Lower LR", high_entropy: "Entropy .02", low_clip: "Clip .10",
  very_high_entropy: "Entropy .05", high_gamma: "Gamma .995", larger_rollout: "Rollout 2048",
};

const pptx = Presentation.create({ slideSize: { width: 1280, height: 720 } });

// 1 — cover
{
  const slide = pptx.slides.add();
  slide.background.fill = C.white;
  addShape(slide, 0, 0, 1280, 16, { fill: C.blue });
  addText(slide, "UCCD2063 • reinforcement learning experiment", 46, 52, 680, 24, { size: 14, bold: true, color: C.blue });
  addText(slide, "PPO Training and\nEvaluation in Godot", 46, 118, 620, 148, { size: 54, bold: true });
  addText(slide, "Platform collector environment\nSeven PPO configurations • seed 123 and four-seed matrix", 48, 316, 590, 68, { size: 22, color: C.muted });
  addShape(slide, 740, 54, 434, 546, { geometry: "roundRect", fill: C.dark, line: { style: "solid", width: 0, fill: C.dark } });
  addText(slide, "EXPERIMENT\nEVIDENCE", 784, 110, 250, 70, { size: 29, bold: true, color: C.white });
  addMetric(slide, 784, 238, 324, "7", "controlled PPO configurations", C.sky);
  addMetric(slide, 784, 350, 324, "50", "episodes per evaluation mode", C.green);
  addMetric(slide, 784, 462, 324, "4", "training seeds in the stability matrix", C.blue);
  addText(slide, "Data source: AS1_PPO_Training_and_Evaluation.ipynb", 46, 638, 645, 24, { size: 16, color: C.muted });
  addText(slide, "01", 1150, 638, 72, 24, { size: 16, bold: true, color: C.muted, align: "right" });
  addNotes(slide, ["Notebook: agent/AS1_PPO_Training_and_Evaluation.ipynb", "Experiment plan: results/experiment_plan.csv"]);
}

// 2 — experimental matrix
{
  const slide = pptx.slides.add();
  addBase(slide, 2, "Experiment matrix", "Seven runs change one PPO setting at a time");
  const values = [["Configuration", "Controlled change", "Modified value"]];
  for (const row of plan) {
    const value = row.name === "baseline" ? "Reference" : row.name === "low_lr" ? "lr = 0.0001" : row.name === "high_entropy" ? "ent_coef = 0.02" : row.name === "low_clip" ? "clip = 0.10" : row.name === "very_high_entropy" ? "ent_coef = 0.05" : row.name === "high_gamma" ? "gamma = 0.995" : "n_steps = 2048";
    values.push([shortName[row.name], row.controlled_change, value]);
  }
  addTable(slide, values, 42, 178, 1192, 362, [260, 640, 292], [1]);
  addShape(slide, 42, 568, 1192, 58, { geometry: "roundRect", fill: C.bluePale, line: { style: "solid", width: 1, fill: C.rule } });
  addText(slide, "All non-listed PPO settings remain fixed, so the deterministic and stochastic results can be attributed to one controlled change per configuration.", 66, 586, 1138, 25, { size: 17, color: C.ink });
  addNotes(slide, ["Generated experiment table: results/experiment_plan.csv", "Notebook: agent/AS1_PPO_Training_and_Evaluation.ipynb"]);
}

// 3 — fixed protocol & time
{
  const slide = pptx.slides.add();
  addBase(slide, 3, "Training protocol", "Each configuration uses the same training and test protocol");
  addShape(slide, 42, 180, 478, 418, { geometry: "roundRect", fill: C.pale, line: { style: "solid", width: 1, fill: C.rule } });
  addText(slide, "Fixed settings", 76, 218, 320, 32, { size: 25, bold: true });
  addText(slide, "Policy                 MlpPolicy\nSeed                   123\nTraining steps    200,704\nBatch size          64\nEpochs               10\nGamma               0.99\nGAE lambda       0.95\nEvaluation       50 deterministic + 50 stochastic", 76, 278, 370, 250, { size: 19, color: C.ink });
  addText(slide, "Recorded wall-clock time", 560, 184, 530, 28, { size: 22, bold: true });
  const chartRows = [...plan].sort((a, b) => Number(trainingByName.get(b.name).training_seconds) - Number(trainingByName.get(a.name).training_seconds));
  addBarChart(slide, 548, 230, 646, 335, chartRows.map((row) => shortName[row.name]), chartRows.map((row) => Number(trainingByName.get(row.name).training_seconds)), { seriesName: "Seconds", min: 0, max: 270, majorUnit: 60 });
  addText(slide, "Across the seven seed-123 training runs, recorded duration ranges from 184.8 to 243.2 seconds.", 560, 581, 600, 28, { size: 16, color: C.muted });
  addNotes(slide, ["Generated training metadata: results/all_training_metadata.csv", "Notebook configuration: agent/AS1_PPO_Training_and_Evaluation.ipynb"]);
}

// 4 — deterministic metric chart
{
  const slide = pptx.slides.add();
  addBase(slide, 4, "Deterministic evaluation", "The baseline is the only configuration with a 100% completion rate");
  const deterministicRows = [policy.find((row) => row.label === "Random agent"), ...plan.map((row) => deterministicByName.get(row.name))];
  const categories = ["Random", ...plan.map((row) => shortName[row.name])];
  addBarChart(slide, 48, 177, 724, 420, categories, deterministicRows.map((row) => Number(row.completion_rate) * 100), { seriesName: "Completion %", min: 0, max: 110, majorUnit: 20, fill: C.blue });
  addMetric(slide, 830, 188, 330, "32.31", "baseline mean reward", C.green);
  addMetric(slide, 830, 302, 330, "2.00", "baseline apples per episode", C.blue);
  addMetric(slide, 830, 416, 330, "50 / 50", "baseline successful episodes", C.green);
  addText(slide, "Higher exploration and a larger rollout batch each complete 34 of 50 episodes; all other variants record zero deterministic completions.", 830, 552, 335, 48, { size: 16, color: C.muted });
  addNotes(slide, ["Generated comparison table: results/policy_comparison.csv", "Deterministic evaluation summary: results/all_experiment_summaries.csv"]);
}

// 5 — deterministic evidence table
{
  const slide = pptx.slides.add();
  addBase(slide, 5, "Deterministic result table", "The 50-episode table compares all deterministic outcomes");
  const values = [["Configuration", "Reward", "Steps", "Distance", "Apples", "Completion"]];
  for (const row of plan) {
    const result = deterministicByName.get(row.name);
    values.push([shortName[row.name], f2(result.mean_reward), f2(result.mean_steps), Math.round(Number(result.mean_distance)).toLocaleString(), f2(result.mean_apples), pct(result.completion_rate)]);
  }
  addTable(slide, values, 42, 183, 1192, 356, [264, 150, 150, 200, 190, 238], [1]);
  addShape(slide, 42, 570, 1192, 54, { geometry: "roundRect", fill: C.bluePale, line: { style: "solid", width: 1, fill: C.rule } });
  addText(slide, "The baseline completes the level in the fewest steps and shortest mean distance while collecting both apples in every deterministic episode.", 66, 587, 1138, 22, { size: 17 });
  addNotes(slide, ["Generated deterministic summary: results/all_experiment_summaries.csv", "Generated comparison table: results/policy_comparison.csv"]);
}

// 6 — stochastic evidence table
{
  const slide = pptx.slides.add();
  addBase(slide, 6, "Stochastic evaluation", "Stochastic testing keeps baseline completion at 98%");
  const values = [["Configuration", "Reward", "Reward SD", "Steps", "Apples", "Completion"]];
  for (const row of plan) {
    const result = stochasticByName.get(row.name);
    values.push([shortName[row.name], f2(result.mean_reward), f2(result.reward_std), f2(result.mean_steps), f2(result.mean_apples), pct(result.completion_rate)]);
  }
  addTable(slide, values, 42, 183, 820, 356, [250, 122, 150, 132, 110, 156], [1]);
  addBarChart(slide, 895, 191, 300, 345, plan.map((row) => shortName[row.name]), plan.map((row) => Number(stochasticByName.get(row.name).completion_rate) * 100), { seriesName: "Completion %", min: 0, max: 110, majorUnit: 20, fill: C.green });
  addText(slide, "The same 50-episode protocol is run with stochastic action selection. The baseline remains the highest-completing configuration.", 42, 583, 1138, 24, { size: 17, color: C.muted });
  addNotes(slide, ["Generated stochastic summary: results/all_stochastic_experiment_summaries.csv", "Notebook evaluation stage: agent/AS1_PPO_Training_and_Evaluation.ipynb"]);
}

// 7 — training curves
{
  const slide = pptx.slides.add();
  addBase(slide, 7, "Learning curves", "Only the baseline reaches a stable rolling reward above 30");
  addShape(slide, 40, 168, 824, 445, { geometry: "roundRect", fill: C.white, line: { style: "solid", width: 1, fill: C.rule } });
  addImage(slide, "results/training_reward_comparison.png", 52, 184, 800, 410, "Training reward curves for all PPO configurations");
  addMetric(slide, 907, 185, 272, "~130k", "baseline reward rise begins", C.blue);
  addMetric(slide, 907, 299, 272, "32.31", "final deterministic mean reward", C.green);
  addMetric(slide, 907, 413, 272, "18.78", "next-highest deterministic mean reward", C.amber);
  addText(slide, "The baseline curve becomes positive near 120k timesteps and stays near 30–32 through the final training updates.", 907, 544, 270, 48, { size: 16, color: C.muted });
  addNotes(slide, ["Generated training figure: results/training_reward_comparison.png", "Generated deterministic summary: results/all_experiment_summaries.csv"]);
}

// 8 — multi-seed stability
{
  const slide = pptx.slides.add();
  addBase(slide, 8, "Four-seed stability matrix", "Seed 123 is a strong run, while completion varies across four training seeds");
  const orderedSeeds = plan.map((row) => seedsByName.get(row.name));
  addBarChart(slide, 48, 180, 678, 377, plan.map((row) => shortName[row.name]), orderedSeeds.map((row) => Number(row.completion_rate_mean) * 100), { seriesName: "Mean completion %", min: 0, max: 50, majorUnit: 10, fill: C.blue });
  const values = [["Configuration", "Mean completion", "SD", "Mean apples", "Seeds"]];
  for (const row of plan) {
    const result = seedsByName.get(row.name);
    values.push([shortName[row.name], pct(result.completion_rate_mean), f2(result.completion_rate_std), f2(result.mean_apples_mean), result.seeds_evaluated]);
  }
  addTable(slide, values, 760, 180, 440, 377, [148, 96, 58, 88, 50], [1]);
  addText(slide, "The multi-seed table includes seeds 123, 203, 521 and 848. Larger rollout has the highest mean completion at 42%, while the seed-123 baseline is the strongest single evaluated run.", 48, 588, 1140, 34, { size: 16, color: C.muted });
  addNotes(slide, ["Generated four-seed summary: results/seed_matrix_summary.csv", "Generated seed evaluation results: results/seed_matrix_evaluation_results.csv"]);
}

// 9 — trajectory and gameplay cue
{
  const slide = pptx.slides.add();
  addBase(slide, 9, "Learned trajectory", "The seed-123 baseline follows a focused route to both apples and the goal");
  addShape(slide, 42, 171, 752, 430, { geometry: "roundRect", fill: C.dark, line: { style: "solid", width: 0, fill: C.dark } });
  addText(slide, "BASELINE POSITION HEATMAP", 84, 202, 668, 28, { size: 18, bold: true, color: C.sky, align: "center" });
  addImage(slide, "results/baseline_position_heatmap.png", 84, 244, 668, 306, "Position heatmap for the seed-123 baseline trajectory");
  addShape(slide, 834, 171, 348, 430, { geometry: "roundRect", fill: C.bluePale, line: { style: "solid", width: 1, fill: C.rule } });
  addText(slide, "Seed-123 evidence", 868, 211, 280, 28, { size: 24, bold: true });
  addText(slide, "Mean reward\n32.31\n\nMean steps\n56.78\n\nMean distance\n1,370 px\n\nApples / completion\n2.00 / 100%", 868, 270, 250, 245, { size: 20 });
  addText(slide, "Play the recorded Godot gameplay here to show the trained policy executing this route in the live environment.", 42, 623, 1128, 24, { size: 16, color: C.muted });
  addNotes(slide, ["Generated trajectory figure: results/baseline_position_heatmap.png", "Generated deterministic summary: results/all_experiment_summaries.csv", "Presentation requirement: 1_FullTime-2026-June_Sept_UCCD2063_-_Question.pdf"]);
}

fs.mkdirSync(RENDER_DIR, { recursive: true });
const exported = await PresentationFile.exportPptx(pptx);
await exported.save(OUT);
for (const [index, slide] of pptx.slides.items.entries()) {
  const png = await pptx.export({ slide, format: "png", scale: 1 });
  await fs.promises.writeFile(path.join(RENDER_DIR, `slide-${String(index + 1).padStart(2, "0")}.png`), new Uint8Array(await png.arrayBuffer()));
}
console.log(`Wrote ${OUT}`);
console.log(`Rendered ${pptx.slides.count} slides to ${RENDER_DIR}`);
