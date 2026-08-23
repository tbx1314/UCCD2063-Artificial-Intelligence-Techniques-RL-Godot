import fs from "fs";
import path from "path";
import { Presentation, PresentationFile } from "@oai/artifact-tool";

const ROOT = "/Users/booxuan/Documents/as_1";
const OUT = path.join(ROOT, "AS1_PPO_Training_and_Evaluation_Presentation.pptx");
const RENDER_DIR = path.join(ROOT, ".tmp_presentation_build", "rendered");

const C = {
  white: "#FFFFFF",
  ink: "#15171A",
  muted: "#5B6470",
  pale: "#F2F4F6",
  rule: "#C7CDD4",
  blue: "#3D8DFF",
  sky: "#6DCBF4",
  bluePale: "#EAF5FB",
  dark: "#182333",
  green: "#31814B",
  red: "#C74634",
};
const FONT = "Helvetica Neue";

function bytes(relativePath) {
  return fs.readFileSync(path.join(ROOT, relativePath));
}

function addShape(slide, x, y, width, height, opts = {}) {
  const shape = slide.shapes.add({
    geometry: opts.geometry ?? "rect",
    position: { left: x, top: y, width, height },
    fill: opts.fill ?? "#FFFFFF",
    line: opts.line ?? { width: 0, fill: opts.fill ?? "#FFFFFF" },
  });
  return shape;
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
    fontSize: opts.size ?? 20,
    color: opts.color ?? C.ink,
    bold: opts.bold ?? false,
    alignment: opts.align ?? "left",
    verticalAlignment: opts.valign ?? "top",
    autoFit: "shrinkText",
  };
  return box;
}

function addImage(slide, relativePath, x, y, width, height, opts = {}) {
  return slide.images.add({
    data: bytes(relativePath),
    position: { left: x, top: y, width, height },
    fit: opts.fit ?? "contain",
    alt: opts.alt ?? path.basename(relativePath),
  });
}

function addSlideBase(slide, number, kicker, title) {
  slide.background.fill = C.white;
  addShape(slide, 0, 0, 1280, 12, { fill: C.blue });
  addText(slide, kicker.toUpperCase(), 42, 34, 900, 22, { size: 13, bold: true, color: C.blue });
  addText(slide, title, 40, 68, 1188, 82, { size: 37, bold: true, color: C.ink });
  addShape(slide, 40, 660, 1198, 1, { fill: C.rule });
  addText(slide, "UCCD2063 • PPO baseline • seed 123", 40, 674, 650, 18, { size: 11, color: C.muted });
  addText(slide, String(number).padStart(2, "0"), 1180, 670, 58, 20, { size: 12, bold: true, color: C.muted, align: "right" });
}

function addNotes(slide, lines) {
  slide.speakerNotes.textFrame.setText(`[Sources]\n${lines.map((line) => `- ${line}`).join("\n")}`);
}

function addMetricCard(slide, x, y, width, height, value, label, accent = C.blue) {
  addShape(slide, x, y, width, height, { geometry: "roundRect", fill: C.pale, line: { width: 1, fill: C.rule } });
  addShape(slide, x, y, 7, height, { geometry: "roundRect", fill: accent, line: { width: 0, fill: accent } });
  addText(slide, value, x + 24, y + 22, width - 42, 52, { size: 30, bold: true, color: C.ink });
  addText(slide, label, x + 24, y + 83, width - 42, 42, { size: 16, color: C.muted });
}

const pptx = Presentation.create({ slideSize: { width: 1280, height: 720 } });

// 1 — cover
{
  const slide = pptx.slides.add();
  slide.background.fill = C.white;
  addShape(slide, 0, 0, 1280, 16, { fill: C.blue });
  addText(slide, "UCCD2063 • Reinforcement learning evidence", 44, 52, 680, 24, { size: 14, bold: true, color: C.blue });
  addText(slide, "PPO for the AS1\nGodot Platform Collector", 44, 118, 635, 158, { size: 54, bold: true, color: C.ink });
  addText(slide, "Baseline policy • seed 123\nTraining and evaluation results", 48, 322, 510, 76, { size: 24, color: C.muted });
  addShape(slide, 704, 54, 492, 548, { geometry: "roundRect", fill: C.bluePale, line: { width: 1, fill: C.rule } });
  addShape(slide, 743, 93, 414, 470, { geometry: "roundRect", fill: C.dark, line: { width: 0, fill: C.dark } });
  addText(slide, "GODOT\nPLATFORM\nCOLLECTOR", 777, 140, 280, 142, { size: 29, bold: true, color: C.white });
  addShape(slide, 778, 365, 250, 12, { fill: C.sky });
  addShape(slide, 1044, 365, 72, 12, { fill: C.blue });
  addImage(slide, "assets/images/player/Run (32x32).png", 804, 420, 112, 112, { alt: "Player character sprite" });
  addImage(slide, "assets/images/Collectibles/Apple.png", 1005, 427, 82, 82, { alt: "Apple collectible sprite" });
  addImage(slide, "assets/images/Snail/Walk (38x24).png", 1010, 516, 112, 71, { alt: "Snail enemy sprite" });
  addText(slide, "Baseline run: 200,704 training steps", 44, 638, 640, 26, { size: 16, color: C.muted });
  addText(slide, "01", 1160, 638, 64, 26, { size: 16, bold: true, color: C.muted, align: "right" });
  addNotes(slide, [
    "Project assets: assets/images/player/Run (32x32).png, assets/images/Collectibles/Apple.png, assets/images/Snail/Walk (38x24).png",
    "Notebook: agent/AS1_PPO_Training_and_Evaluation.ipynb",
  ]);
}

// 2 — learning loop
{
  const slide = pptx.slides.add();
  addSlideBase(slide, 2, "Agent–environment loop", "The agent receives 12 normalized state values and selects one of six actions");
  addText(slide, "State representation", 52, 182, 280, 26, { size: 21, bold: true, color: C.ink });
  const states = ["Player position", "Velocity", "Floor / wall contact", "Target direction", "Enemy direction", "Apples remaining"];
  states.forEach((state, index) => {
    const col = index < 3 ? 0 : 1;
    const row = index % 3;
    const x = 52 + col * 188;
    const y = 228 + row * 74;
    addShape(slide, x, y, 170, 54, { geometry: "roundRect", fill: C.pale, line: { width: 1, fill: C.rule } });
    addText(slide, state, x + 15, y + 16, 140, 22, { size: 15, color: C.ink });
  });
  addShape(slide, 432, 250, 338, 210, { geometry: "roundRect", fill: C.dark, line: { width: 0, fill: C.dark } });
  addText(slide, "PPO\npolicy network", 474, 294, 250, 90, { size: 31, bold: true, color: C.white, align: "center" });
  addText(slide, "observations → action", 474, 397, 250, 28, { size: 16, color: C.sky, align: "center" });
  addShape(slide, 814, 202, 356, 314, { geometry: "roundRect", fill: C.bluePale, line: { width: 1, fill: C.rule } });
  addText(slide, "Action space", 846, 235, 280, 28, { size: 21, bold: true, color: C.ink });
  addText(slide, "0  no input\n1  move left\n2  move right\n3  jump\n4  left + jump\n5  right + jump", 846, 286, 260, 165, { size: 19, color: C.ink });
  addText(slide, "Godot returns next state, reward, terminal status and score through the WebSocket environment.", 52, 562, 1118, 48, { size: 20, color: C.muted });
  addNotes(slide, [
    "Assignment brief, Section 3.1: game returns state, reward, status and score",
    "Notebook environment definition: agent/AS1_PPO_Training_and_Evaluation.ipynb",
  ]);
}

// 3 — reward design
{
  const slide = pptx.slides.add();
  addSlideBase(slide, 3, "Reward function", "The reward signal prioritizes safe, efficient task completion");
  addText(slide, "Event", 62, 178, 260, 26, { size: 18, bold: true, color: C.muted });
  addText(slide, "Reward", 560, 178, 140, 26, { size: 18, bold: true, color: C.muted });
  const rewards = [
    ["Every step", "−0.01", C.muted],
    ["New waypoint", "+4", C.blue],
    ["Apple collected", "+5", C.green],
    ["Level completed", "+20", C.green],
    ["Enemy hit or fall", "−10", C.red],
    ["Timeout", "−8", C.red],
  ];
  rewards.forEach(([event, reward, color], i) => {
    const y = 216 + i * 57;
    addShape(slide, 52, y, 650, 45, { fill: i % 2 ? C.white : C.pale, line: { width: 0, fill: C.white } });
    addText(slide, event, 66, y + 13, 430, 20, { size: 17, color: C.ink });
    addText(slide, reward, 560, y + 10, 100, 24, { size: 21, bold: true, color, align: "right" });
  });
  addShape(slide, 772, 186, 396, 367, { geometry: "roundRect", fill: C.dark, line: { width: 0, fill: C.dark } });
  addText(slide, "Reward events in the game", 810, 219, 300, 28, { size: 21, bold: true, color: C.white });
  addImage(slide, "assets/images/Collectibles/Apple.png", 820, 289, 104, 104, { alt: "Apple collectible sprite" });
  addText(slide, "+5", 943, 326, 70, 38, { size: 30, bold: true, color: C.sky });
  addImage(slide, "assets/images/Snail/Walk (38x24).png", 819, 438, 150, 96, { alt: "Snail enemy sprite" });
  addText(slide, "−10", 991, 469, 95, 38, { size: 30, bold: true, color: "#FF9285" });
  addText(slide, "The step penalty discourages waiting; task and safety events dominate the return.", 52, 583, 1120, 35, { size: 18, color: C.muted });
  addNotes(slide, [
    "Notebook reward design: agent/AS1_PPO_Training_and_Evaluation.ipynb",
    "Project assets: assets/images/Collectibles/Apple.png and assets/images/Snail/Walk (38x24).png",
  ]);
}

// 4 — training protocol
{
  const slide = pptx.slides.add();
  addSlideBase(slide, 4, "Training protocol", "Baseline PPO uses a reproducible 200,704-step training protocol");
  const paramsLeft = [
    ["Policy", "MlpPolicy"],
    ["Seed", "123"],
    ["Learning rate", "0.0003"],
    ["Rollout steps", "1,024"],
    ["Batch size", "64"],
  ];
  const paramsRight = [
    ["Epochs", "10"],
    ["Discount (γ)", "0.99"],
    ["GAE λ", "0.95"],
    ["Clip range", "0.20"],
    ["Entropy coefficient", "0.01"],
  ];
  function parameterColumn(items, x) {
    items.forEach(([label, value], i) => {
      const y = 186 + i * 69;
      addShape(slide, x, y, 474, 54, { geometry: "roundRect", fill: i % 2 ? C.white : C.pale, line: { width: 1, fill: C.rule } });
      addText(slide, label, x + 19, y + 17, 260, 22, { size: 17, color: C.muted });
      addText(slide, value, x + 282, y + 14, 167, 26, { size: 20, bold: true, color: C.ink, align: "right" });
    });
  }
  parameterColumn(paramsLeft, 52);
  parameterColumn(paramsRight, 564);
  addMetricCard(slide, 1056, 186, 140, 160, "218.5 s", "training time", C.blue);
  addMetricCard(slide, 1056, 366, 140, 160, "50", "test episodes", C.green);
  addText(slide, "The stored model and evaluation records use the same seed and configuration shown here.", 52, 578, 1100, 36, { size: 18, color: C.muted });
  addNotes(slide, [
    "Results metadata: results/all_training_metadata.csv",
    "Experiment plan: results/experiment_plan.csv",
    "Notebook configuration: agent/AS1_PPO_Training_and_Evaluation.ipynb",
  ]);
}

// 5 — training curve
{
  const slide = pptx.slides.add();
  addSlideBase(slide, 5, "Learning curve and checkpoint screening", "Rolling reward rises sharply after approximately 130k timesteps");
  addShape(slide, 42, 166, 777, 446, { geometry: "roundRect", fill: C.white, line: { width: 1, fill: C.rule } });
  addImage(slide, "results/training_reward_comparison.png", 54, 181, 752, 410, { fit: "contain", alt: "Rolling reward during baseline PPO training" });
  addMetricCard(slide, 855, 180, 335, 118, "190k", "checkpoint selected during screening", C.blue);
  addMetricCard(slide, 855, 320, 335, 118, "32.27", "screened mean reward at that checkpoint", C.green);
  addShape(slide, 855, 460, 335, 133, { geometry: "roundRect", fill: C.bluePale, line: { width: 1, fill: C.rule } });
  addText(slide, "The curve moves from negative reward early in training to a stable positive band near 30–32.", 879, 484, 285, 77, { size: 18, color: C.ink });
  addNotes(slide, [
    "Training figure: results/training_reward_comparison.png",
    "Checkpoint data: results/checkpoint_screening.csv",
  ]);
}

// 6 — policy comparison
{
  const slide = pptx.slides.add();
  addSlideBase(slide, 6, "Deterministic policy evaluation", "PPO completes every test episode while the random control completes none");
  addShape(slide, 42, 164, 742, 455, { geometry: "roundRect", fill: C.white, line: { width: 1, fill: C.rule } });
  addImage(slide, "results/all_policy_metric_comparison.png", 55, 180, 716, 418, { fit: "contain", alt: "Policy comparison for reward, apples and completion rate" });
  addMetricCard(slide, 832, 178, 350, 116, "32.29", "PPO mean reward", C.green);
  addMetricCard(slide, 832, 316, 350, 116, "100%", "PPO completion rate", C.green);
  addMetricCard(slide, 832, 454, 350, 116, "2.0", "PPO mean apples collected", C.blue);
  addText(slide, "Random control: −12.39 mean reward, 0 apples, 0% completion (50 episodes).", 832, 590, 350, 24, { size: 15, color: C.muted });
  addNotes(slide, [
    "Policy comparison figure: results/all_policy_metric_comparison.png",
    "Policy data: results/policy_comparison.csv",
  ]);
}

// 7 — behavior and reliability
{
  const slide = pptx.slides.add();
  addSlideBase(slide, 7, "Terminal outcomes and repeatability", "Evaluation episodes show consistent rewards, apples and successful endings");
  addShape(slide, 42, 171, 548, 358, { geometry: "roundRect", fill: C.white, line: { width: 1, fill: C.rule } });
  addImage(slide, "results/all_terminal_outcomes.png", 56, 188, 520, 320, { fit: "contain", alt: "Terminal outcomes for random agent and baseline PPO" });
  addShape(slide, 626, 171, 552, 358, { geometry: "roundRect", fill: C.white, line: { width: 1, fill: C.rule } });
  addImage(slide, "results/all_evaluation_consistency.png", 642, 188, 520, 320, { fit: "contain", alt: "Reward and apples collected across evaluation episodes" });
  addMetricCard(slide, 42, 550, 350, 78, "100%", "baseline successful terminal state", C.green);
  addMetricCard(slide, 424, 550, 350, 78, "2 apples", "collected in every baseline episode", C.blue);
  addMetricCard(slide, 806, 550, 372, 78, "50 / 50", "deterministic test episodes", C.green);
  addNotes(slide, [
    "Terminal outcomes figure: results/all_terminal_outcomes.png",
    "Evaluation consistency figure: results/all_evaluation_consistency.png",
    "Episode data: results/all_evaluations.csv and results/random_agent_results.csv",
  ]);
}

// 8 — learned trajectory
{
  const slide = pptx.slides.add();
  addSlideBase(slide, 8, "Learned trajectory", "The baseline follows a repeatable route to both apples and the goal");
  addShape(slide, 44, 170, 746, 432, { geometry: "roundRect", fill: C.dark, line: { width: 0, fill: C.dark } });
  addText(slide, "BASELINE POSITION HEATMAP", 88, 205, 640, 34, { size: 19, bold: true, color: C.sky, align: "center" });
  addImage(slide, "results/baseline_position_heatmap.png", 88, 255, 650, 294, { fit: "contain", alt: "Baseline agent position heatmap showing its route" });
  addShape(slide, 828, 170, 354, 432, { geometry: "roundRect", fill: C.bluePale, line: { width: 1, fill: C.rule } });
  addText(slide, "Episode-level evidence", 860, 210, 290, 30, { size: 23, bold: true, color: C.ink });
  addText(slide, "Policy\nBaseline PPO\n\nSeed\n123\n\nMean steps\n58.28\n\nMean distance\n1,595.28 px\n\nApples / completion\n2.0 / 100%", 860, 266, 260, 284, { size: 19, color: C.ink });
  addText(slide, "The spatial trace matches the evaluation records: each baseline episode collects both apples and reaches a successful terminal state.", 44, 620, 1135, 25, { size: 16, color: C.muted });
  addNotes(slide, [
    "Trajectory figure: results/baseline_position_heatmap.png",
    "Notebook: agent/AS1_PPO_Training_and_Evaluation.ipynb",
    "Evaluation data: results/all_experiment_summaries.csv and results/all_evaluations.csv",
  ]);
}

fs.mkdirSync(RENDER_DIR, { recursive: true });
const exportedPptx = await PresentationFile.exportPptx(pptx);
await exportedPptx.save(OUT);
for (let index = 0; index < pptx.slides.count; index += 1) {
  const slide = pptx.slides.items[index];
  const png = await pptx.export({ slide, format: "png", scale: 1 });
  const outputPath = path.join(RENDER_DIR, `slide-${String(index + 1).padStart(2, "0")}.png`);
  await fs.promises.writeFile(outputPath, new Uint8Array(await png.arrayBuffer()));
}
console.log(`Wrote ${OUT}`);
console.log(`Rendered ${pptx.slides.count} slides to ${RENDER_DIR}`);
