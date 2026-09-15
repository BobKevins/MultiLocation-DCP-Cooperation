# 最终版代码实施说明

## 1. 功能

该版本统一求解五个 DCP 的集中式 Stage 1、分布式 ADMM Stage 1 和逐 DCP
Stage 2 用户响应模型，并提供 R1C5、R2C2、R2C4 的独立运行入口。

## 2. 输入

唯一输入工作簿为 `Input_Data/input_parameters.xlsx`。

- `Hours`：时段标签。
- `Price_Data`：三类地点电价。
- `PV_Data`：光伏基准出力。
- `WT_Data`：风电基准出力。
- `Workload_Data`：Hour、Workload_Type、DCP1--DCP5。每个时段分别保存
  Interactive 和 Batch 两条实际输入记录。

## 3. 数据传递

```text
input_parameters.xlsx
        |
        v
prepare_case -> cfg
        |
        +-> solve_stage1_centralized -> centralized_result
        |
        +-> solve_stage1_admm        -> admm_result
                                          |
                                          v
                              solve_stage2_users (DCP1--DCP5)
                                          |
                                          v
                                      outputs/
```

集中式与 ADMM 均调用 `build_stage1_dcp`。五个 DCP 的差异参数存放在
`cfg.dcp(dc)`，不维护五份重复模型。

## 4. 核心模型

- R1C1：一个无序 DCP 对使用一个有符号规范流；正负号表示方向，绝对值辅助
  变量用于计算交互成本，并显式建立双向变量的反对称关系。
- R1C2：批处理调整采用净调整量。对角元素为非正移出量，未来有效时段为
  非负迁入量，逐源时段行和为零。
- R1C3--R1C4：连续激励率与二元档位的乘积通过 `omega` 和四组凸包约束
  精确线性化。
- R1C5：集中式 Stage 1 与 ADMM Stage 1 使用相同输入、约束和物理成本口径。
- R1C6：Stage 2 将迁移后负荷闭合为本地保留和迁入两类代表性用户组。
- 储能：DCP1--DCP3 初始能量为 50 kWh；能量递推包含充放电效率。

## 5. 需要重点理解的文件

- `prepare_case.m`：所有输入、参数、拓扑和索引。
- `build_stage1_dcp.m`：单个 DCP 的 Stage 1 物理模型。
- `solve_stage1_admm.m`：共识、对偶变量、残差与自适应罚因子。
- `solve_stage2_users.m`：用户响应、批处理时间调整、服务器、能源和完整成本。
- `build_stage2_user_groups.m`：R2C4 中用户组数量扩展方式。

其余导出和汇总函数可以作为结果处理模块使用。

## 6. 输出

公开版本的最终结果统一放在 `Results/`：

- `paper_case_figure_data.xlsx` 保存正文 Fig. 5--13、Table 1 和集中式--ADMM
  对比表的数据；
- `reviewer_response_figure_data.xlsx` 保存敏感性、交叉验证和扩展算例数据。

公开包不预置 MAT 工作区、检查 CSV、收敛图片和逐 DCP 调试输出。

## 7. 验证

正式修改后应依次检查：MATLAB Code Analyzer、求解状态、Stage 1 成本误差、
逐 DCP 成本误差、用户组负荷闭合、初始 SOC、SOC 递推和电力平衡。
