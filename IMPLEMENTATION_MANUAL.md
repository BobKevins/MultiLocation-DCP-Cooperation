
## 1. 功能

该版本统一求解五个 DCP 的集中式 Stage 1、分布式 ADMM Stage 1 和逐 DCP
Stage 2 用户响应模型，并提供正文、敏感性、交叉验证和扩展算例入口。

## 2. 输入

主算例基础输入工作簿为 `Input_Data/input_parameters.xlsx`；公开负荷和三 DCP
拓扑使用对应专项 Input_Data 中随代码提供的工作簿。

- `Hours`：时段标签。
- `Price_Data`：三类地点电价。
- `PV_Data`：光伏基准出力。
- `WT_Data`：风电基准出力。
- `Workload_Data`：Hour、Workload_Type、DCP1--DCP5。每个时段分别保存
  Interactive 和 Batch 两条实际输入记录。

## 3. 输出

公开版本的最终结果统一放在 `Results/`：

- `paper_case_figure_data.xlsx` 保存正文 Fig. 5--13、Table 1 和集中式--ADMM
  对比表的数据；
- `reviewer_response_figure_data.xlsx` 保存敏感性、交叉验证和扩展算例数据。
