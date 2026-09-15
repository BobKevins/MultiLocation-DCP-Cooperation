# Response_R1C5_R2C2

- `run_r1c5_stage1_comparison.m`：只比较集中式和 ADMM 的 Stage 1 结果。
- `run_r2c2_sensitivity.m`：分别测试 ADMM 初始罚因子、停止容差、成本 Big-M
  和时间 Big-M。运行前先执行 R1C5 入口。

R2C2 设置：罚因子和容差取基准的 0.1、1、10 倍；成本 Big-M 为
145、725、1450；时间 Big-M 为 24、120、240 h。

最终公开数据位于根目录 `Results/reviewer_response_figure_data.xlsx`。
