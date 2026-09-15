# R2C5：Forecast perturbation out-of-sample test

本目录在当前五 DCP 正式模型基础上检查 day-ahead cooperative schedule 在
workload 与 renewable forecast deviation 下的运行表现。

- 扰动水平：`[-10%, -5%, 0, 5%, 10%]`。
- workload：interactive 与 batch 同时乘以 `1 + xi`。
- renewable：PV 与 WT 可用出力同时乘以 `1 - xi`。
- 任务迁移：优先保持 day-ahead 绝对迁移量；当源 DCP 的 realized workload
  不足时，按原链路比例缩减至全部可用任务，本地剩余量取零。
- 电力交互：保持 day-ahead 绝对交易计划。
- 购售电偏差：相对 nominal Stage 2 购售电计划采用 10% 不利偏差结算。
- Stage 2 成本 Big-M：固定为 `220 USD`，并对每个扰动场景执行充分性审计；
  本次最大需求为 `213.838614 USD`。
- realized stage：只重新求解各 DCP 的本地 Stage 2，不重新运行 ADMM。

运行入口为 `run_r2c5_out_of_sample.m`。输出保存在 `outputs/`。
