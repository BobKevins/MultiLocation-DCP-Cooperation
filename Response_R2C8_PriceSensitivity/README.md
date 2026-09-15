# R2C8：Location 1 电价敏感性

本目录对应 Reviewer 2 Comment 8。程序将 DCP1--DCP3 所在 Location 1 的
24 h 电价同时缩放为基准值的 `0.8、0.9、1.0、1.1、1.2` 倍。M2 没有
跨 DCP 耦合，复用已有独立优化结果；五个 M5 场景采用 ADMM 分布式求解。

## 参数口径

- 交互式延时集合：`[0.05, 0.10, 0.15, 0.20, 0.25]` s；
- 批处理延时集合：`[1, 2, 4, 6]` h；
- 成本 Big-M：`200 USD`；
- 时间 Big-M：`24 h`；
- 正式 Gurobi MIPGap：`1e-6`。

## 文件

- `run_r2c8_price_sensitivity.m`：复用 M2、逐倍率运行 M5 ADMM 并导出结果；
- `prepare_r2c8_case.m`：继承正式模型，只覆盖电价、时延集合和方法开关；
- `audit_r2c8_big_m.m`：逐场景核验 `M_cost=200` 是否充分；

## 运行

入口中的 `admm_time_limit_seconds = 1800` 是单个 ADMM 场景的时间上限，
可以在运行前直接修改。

```matlab
run('Response_R2C8_PriceSensitivity/run_r2c8_price_sensitivity.m')
```

最终公开数据位于根目录 `Results/reviewer_response_figure_data.xlsx`。

## 已有集中式参考结果

| Location 1 price factor | M2 total cost ($) | M5 total cost ($) | Cooperative saving (%) |
|---:|---:|---:|---:|
| 0.8 | 5652.467 | 5132.999 | 9.1901 |
| 0.9 | 5825.672 | 5299.417 | 9.0334 |
| 1.0 | 5997.922 | 5456.589 | 9.0253 |
| 1.1 | 6170.167 | 5601.181 | 9.2216 |
| 1.2 | 6342.396 | 5749.763 | 9.3440 |

- 十个场景均成功求解，最大 Stage 2 MIP gap 为 0；
- Big-M 最大需求为 `194.3987 USD`，固定值 `200 USD` 充分；
- 基准电价下 M5 总成本为 `5456.5894 USD`，与正式五档/四档基准结果一致。
