function export_user_sensitivity_sheets(project_root, result)
%EXPORT_USER_SENSITIVITY_SHEETS 仅导出当前 Fig. 9 求解产生的绘图数值。

c = result.coefficient_plot;
d = result.delay_plot;
inter = table(c.InterCoefficientFactor, c.Inter_DCP_OperationCost_USD, ...
    c.Inter_UserPayment_USD, 'VariableNames', ...
    {'CoefficientFactor', 'DCP_OperationCost_USD', 'UserPayment_USD'});
batch = table(c.BatchCoefficientFactor, c.Batch_DCP_OperationCost_USD, ...
    c.Batch_UserPayment_USD, 'VariableNames', ...
    {'CoefficientFactor', 'DCP_OperationCost_USD', 'UserPayment_USD'});
write_final_result_sheet(project_root, 'paper', 'Fig09_InterCoeff', inter);
write_final_result_sheet(project_root, 'paper', 'Fig09_BatchCoeff', batch);
write_final_result_sheet(project_root, 'paper', 'Fig09_Delay', d);
end
