function export_r2c4_results(cfg, summary_table, repeat_table, per_dcp_table)
%EXPORT_R2C4_RESULTS 导出 R2C4 汇总、重复试验和逐 DCP 数据。

%% ================================== 00 输出路径 ==================================
if ~isfolder(cfg.output_directory)
    mkdir(cfg.output_directory);
end

summary_file = fullfile(cfg.output_directory, 'r2c4_user_scalability_summary.csv');
repeat_file = fullfile(cfg.output_directory, 'r2c4_user_scalability_repeats.csv');
per_dcp_file = fullfile(cfg.output_directory, 'r2c4_user_scalability_per_dcp.csv');
workspace_file = fullfile(cfg.output_directory, 'r2c4_user_scalability_results.mat');

%% ================================== 01 表格与工作区 ==================================
writetable(summary_table, summary_file);
writetable(repeat_table, repeat_file);
writetable(per_dcp_table, per_dcp_file);
save(workspace_file, 'cfg', 'summary_table', 'repeat_table', ...
    'per_dcp_table', '-v7.3');

fprintf('R2C4 结果已写入：%s\n', cfg.output_directory);
end
