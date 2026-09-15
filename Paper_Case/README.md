# Paper_Case

运行 `run_paper_case.m`，依次完成集中式 Stage 1、ADMM Stage 1、Stage 1
误差验证，以及两类 Stage 1 结果驱动的五个 DCP Stage 2 求解。

如只需更新 Fig. 11 的五个 DCP 收敛数据，运行
`run_figure11_dcp_convergence.m`。该入口只执行集中式 Stage 1 和 ADMM Stage 1，
不会运行 Stage 2。结果写入 `outputs/paper_case_figure_data.xlsx`：

- `Fig11_Origin`：Iteration 与 DCP1--DCP5 无量纲相对成本误差，可直接复制到 Origin；
- `Fig11_Audit`：各轮 ADMM 成本、集中式参考成本及相对误差，用于核查数据来源。

运行完整入口 `run_paper_case.m` 后，同一工作簿还会整理 Fig. 5--13 和正文结果表：

- `Fig05_Origin`--`Fig13_Origin`：按现有 Origin 工作表列顺序整理的数据；
- `Fig08_Book1`、`Fig08_Book2`：分别对应 Fig. 8 Origin 工程的两个 Book；
- `Table01_Origin`：不同交易策略 M2--M5 的成本构成和总运行成本；
- `Table02_ADMM`：集中式与分布式 ADMM 的成本、偏差和迭代次数。

Fig. 5--9、Fig. 12--13 和正文结果表从根目录 `Results` 中的正式论文快照读取；
Fig. 10--11 使用当前运行得到的交互计划和收敛历史。统一导出不增加优化求解。
