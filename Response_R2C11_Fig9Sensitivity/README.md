# R2C11：Fig. 9 DCP1 单园区敏感性分析

本目录对应 Reviewer 2 Comment 11。程序使用与原 Fig. 7/9 一致的 DCP1 单园区，
任务迁移和 DCP 间电力交易均固定为零，仅重新求解 DCP1 的完整 Stage 2 用户响应
与本地运行模型。除本目录明确覆盖的敏感性参数外，其余输入、约束和求解设置均
继承 `Final_Code_npjRevise` 当前基础版。

## 分析场景

### 1. 不便系数

- 交互式不便系数基准值：`0.0035`；
- 批处理不便系数基准值：`1e-5`；
- 两类系数分别使用 `0.8、0.9、1.0、1.1、1.2` 倍；
- 测试某一类系数时，另一类系数保持基准值。

### 2. 延时容忍度

- 交互式最大可选延时依次放宽为 `0.05、0.10、0.15、0.20、0.25 s`；
- 批处理最大可选延时依次放宽为 `1、2、4、6 h`；
- 测试某一类延时时，另一类保持完整候选集合；
- 每个场景仅保留不超过当前上限的候选档位，用户仍根据原有最优性约束自主
  选择延时，因此补偿和运行成本的经济含义保持不变。

## 参数口径

- 交互式延时集合：`[0.05, 0.10, 0.15, 0.20, 0.25] s`；
- 批处理延时集合：`[1, 2, 4, 6] h`；
- 成本 Big-M：`250 USD`；
- 时间 Big-M：`24 h`；
- Gurobi MIPGap：`1e-6`；
- 单个 DCP Stage 2 求解时间上限：入口默认 `300 s`，可直接修改。

每个场景运行前仅对 DCP1 执行成本 Big-M 边界核验。`250 USD` 覆盖交互式不便
系数为当前基准值 `0.0035` 的 `1.2` 倍时所需的 `225.8874864 USD` 上界。

## 文件

- `run_r2c11_fig9_sensitivity.m`：正式入口，逐场景求解并输出 CSV/MAT/XLSX；
- `prepare_r2c11_case.m`：继承基础模型，仅覆盖当前敏感性参数；
- `audit_r2c11_big_m.m`：逐场景核验成本 Big-M；
- 根目录 `Results/paper_case_figure_data.xlsx`：论文 Fig. 9 最终作图数据。

## 运行

在 `Final_Code_npjRevise` 目录运行：

```matlab
run('Response_R2C11_Fig9Sensitivity/run_r2c11_fig9_sensitivity.m')
```

MATLAB 运行完成后直接生成：

`outputs/r2c11_fig9_origin_data.xlsx`

Excel 中四个 Origin 直贴 Sheet 与最终 `.opju` 工作簿同名：

- `Book1intercos`：交互式不便系数；
- `Book1batchcos`：批处理不便系数；
- `Book1intertol`：交互式最大可选延时；
- `Book1batchtol`：批处理最大可选延时；
- 每个 Sheet 按 Origin 物理列 `A(X)、B(Y)、C(Y)、D(X)` 排列；
- `D=A+0.01`，用于错开运行成本和用户补偿两组棒线/散点；
- `Scenario_Details` 和 `BigM_Audit` 用于核查，不需要粘贴到 Origin。
