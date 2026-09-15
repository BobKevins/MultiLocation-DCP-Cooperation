# Response_R2C4

`run_r2c4_user_scalability.m` 对每个 DCP 测试 2、4、6、8、10 个代表性用户组。
每种规模运行一次，Stage 2 使用 MIPGap=1e-4、Symmetry=2、成本 Big-M=145
和时间 Big-M=24 h。

本验证固定使用 4 档交互式延时 `[0.05, 0.10, 0.15, 0.20] s` 与 3 档批处理
延时 `[1, 2, 4] h`，共 12 种组合。最终公开结果汇总在根目录
`Results/reviewer_response_figure_data.xlsx` 的 `UserGroup_Validation` 工作表。
