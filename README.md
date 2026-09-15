# Cooperative Sharing of Electricity and Computing Resources

## 目录结构

```text
Final_Code_npjRevise_foropen_v2/
├── Input_Data/                         基础输入数据
├── Common_Functions/                   公共模型与求解函数
├── Paper_Case/                         正文主算例
├── Response_R1C5_R2C2/                 集中式对比、ADMM 与 Big-M 敏感性
├── Response_R2C4/                      用户群组数量算例
├── Response_R2C5_OutOfSampleForecast/  预测偏差敏感性
├── Response_R2C8_PriceSensitivity/     电价敏感性
├── Response_R2C10_PublicTrace/         公开负荷交叉验证
├── Response_R2C11_Fig9Sensitivity/     正文 Fig. 9 敏感性分析
├── Response_R2C15_Gao3DCP/             三 DCP 扩展验证
└── Results/                            当前运行生成的最终图表数据
```

## 最终结果

`Results/` 中的两份汇总工作簿由运行生成，不作为求解输入：

- `paper_case_figure_data.xlsx`：正文 Fig. 5--13、Table 1 和集中式--ADMM 对比表；
- `reviewer_response_figure_data.xlsx`：审稿回复中的 ADMM、Big-M、电价、预测偏差、
  用户群组数量、公开负荷和三 DCP 扩展验证数据。