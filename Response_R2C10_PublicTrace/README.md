# R2C10：Google/Alibaba 公共负荷交叉验证

本目录对应 Reviewer 2 Comment 10。Google 和 Alibaba 公共数据仅提供 24 h
workload shape；每个 DCP 的 interactive 和 batch 日总量分别保持正式基准不变。
M2 没有跨 DCP 耦合，复用已有独立优化结果；M3--M5 采用 ADMM 分布式求解。

## 参数口径

- 交互式延时集合：`[0.05, 0.10, 0.15, 0.20, 0.25]` s；
- 批处理延时集合：`[1, 2, 4, 6]` h；
- 成本 Big-M：`220 USD`（覆盖全部 Google/Alibaba 场景的审计需求）；
- 时间 Big-M：`24 h`；
- 正式 Gurobi MIPGap：`1e-6`。

## M2--M5

- M2：任务迁移和电力交互均关闭；
- M3：仅允许任务迁移；
- M4：仅允许电力交互；
- M5：同时允许任务迁移和电力交互。

## 文件

- `run_r2c10_public_trace.m`：复用 M2，并运行 Google/Alibaba 下的 M3--M5 ADMM；
- `prepare_r2c10_case.m`：读取公共曲线、保持日总量并设置方法开关；
- `audit_r2c10_big_m.m`：逐场景核验 `M_cost=220` 是否充分；
- `Input_Data/public_workload_profiles.xlsx`：正式公共负荷曲线和来源；

## 运行

入口中的 `admm_time_limit_seconds = 1800` 是单个 ADMM 场景的时间上限，
可以在运行前直接修改。

```matlab
run('Response_R2C10_PublicTrace/run_r2c10_public_trace.m')
```

最终公开数据位于根目录 `Results/reviewer_response_figure_data.xlsx`。

## 已有集中式参考结果

| Workload trace | M2 total cost ($) | M3 total cost ($) | M4 total cost ($) | M5 total cost ($) | M3 saving vs. M2 (%) | M4 saving vs. M2 (%) | M5 saving vs. M2 (%) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Google | 5556.433 | 5278.210 | 5361.544 | 5206.650 | 5.0072 | 3.5074 | 6.2951 |
| Alibaba | 5634.829 | 5338.735 | 5448.893 | 5297.522 | 5.2547 | 3.2998 | 5.9861 |

- 八个场景均成功求解，最大 Stage 2 MIP gap 为 0；
- 工作负荷核算误差不超过 `1.46e-11`；
- 储能能量平衡误差和初始 SOC 误差均为 0；
- 最大功率平衡误差为 `5.87e-8`；
- Big-M 最大需求为 `210.3244 USD`，固定值 `220 USD` 的最小裕度为 `9.6756 USD`。
