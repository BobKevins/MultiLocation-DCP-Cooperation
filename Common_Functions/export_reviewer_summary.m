function export_reviewer_summary(project_root, case_kind, first_table, second_table)
%EXPORT_REVIEWER_SUMMARY 当前专项求解结束后，更新审稿结果工作簿。
% 输入必须是当前运行构造的 table，不读取旧 CSV 或旧 Excel。

switch string(case_kind)
    case "algorithm"
        assert(nargin == 4, '算法敏感性需要 ADMM 与 Big-M 两个结果表。');
        t = first_table;
        admm = table(t.ParameterType, t.Multiplier, t.Stage1OperatingCost_USD, ...
            t.RelativeGapToCentralizedStage1_Percent, t.ADMMIterations, ...
            'VariableNames', {'Parameter', 'ScalingFactor', ...
            'OperatingCost_USD', 'Gap_Percent', 'Iteration'});
        t = second_table;
        bigm = table(t.ParameterType, t.Multiplier, t.InteractionWallTime_s, ...
            t.MaximumSingleDCPMIPGap, t.SolverStatus, ...
            'VariableNames', {'Parameter', 'ScalingFactor', 'Time_s', ...
            'MaximumMIPGap', 'Status'});
        write_final_result_sheet(project_root, 'reviewer', 'ADMM_Sensitivity', admm);
        write_final_result_sheet(project_root, 'reviewer', 'BigM_Sensitivity', bigm);
    case "users"
        t = first_table;
        data = t(:, {'UserGroupsPerDCP', 'MedianTotalStage2Runtime_s', ...
            'MedianMaximumSingleDCPRuntime_s', 'MaximumMIPGap'});
        write_final_result_sheet(project_root, 'reviewer', 'UserGroup_Validation', data);
    case "price"
        write_final_result_sheet(project_root, 'reviewer', 'Price_Sensitivity', first_table);
    case "forecast"
        write_final_result_sheet(project_root, 'reviewer', 'Forecast_Sensitivity', first_table);
    case "traces"
        write_final_result_sheet(project_root, 'reviewer', 'PublicTrace_Validation', first_table);
    case "published"
        t = first_table;
        cost = [t.M2TotalCost_USD; t.M3TotalCost_USD; t.M4TotalCost_USD; t.M5TotalCost_USD];
        saving = [NaN; t.M3SavingVsM2_Percent; t.M4SavingVsM2_Percent; t.M5SavingVsM2_Percent];
        data = [{'OperationStrategy', 'OperatingCost_USD', 'SavingVsM2_Percent'}; ...
            [cellstr(["M2"; "M3"; "M4"; "M5"]), num2cell([cost, saving])]];
        data{2, 3} = '--';
        write_final_result_sheet(project_root, 'reviewer', 'PublishedDCP_Validation', data);
    otherwise
        error('未知审稿结果类型：%s。', case_kind);
end
end
