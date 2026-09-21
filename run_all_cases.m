function run_all_cases()
%RUN_ALL_CASES 顺序求解全部正文、敏感性、交叉验证及扩展算例。
% 主入口已经计算 Fig. 9，整套运行不再次调用同一敏感性专项。

%% ================================== 00 项目路径与入口 ==================================
project_root = fileparts(mfilename('fullpath'));
entries = { ...
    fullfile('Paper_Case', 'run_paper_case.m'); ...
    fullfile('Response_R1C5_R2C2', 'run_r1c5_r2c2.m'); ...
    fullfile('Response_R2C4', 'run_r2c4_user_scalability.m'); ...
    fullfile('Response_R2C8_PriceSensitivity', 'run_r2c8_price_sensitivity.m'); ...
    fullfile('Response_R2C5_OutOfSampleForecast', 'run_r2c5_out_of_sample.m'); ...
    fullfile('Response_R2C10_PublicTrace', 'run_r2c10_public_trace.m'); ...
    fullfile('Response_R2C15_Gao3DCP', 'run_r2c15_gao_3dcp.m')};

% 整套复现从空 Results 开始；上次输出可恢复地移入历史目录，避免混入旧 Sheet。
result_names = {'paper_case_figure_data.xlsx', 'reviewer_response_figure_data.xlsx'};
history_directory = fullfile(project_root, 'Run_History', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS')));
for index = 1:numel(result_names)
    previous_file = fullfile(project_root, 'Results', result_names{index});
    if isfile(previous_file)
        if ~isfolder(history_directory)
            mkdir(history_directory);
        end
        movefile(previous_file, fullfile(history_directory, result_names{index}));
    end
end

%% ================================== 01 各算例独立运行 ==================================
for index = 1:numel(entries)
    fprintf('\n================ %d/%d: %s ================\n', ...
        index, numel(entries), entries{index});
    run_one_entry(fullfile(project_root, entries{index}));
end

%% ================================== 02 最终工作簿完整性 ==================================
paper = fullfile(project_root, 'Results', 'paper_case_figure_data.xlsx');
reviewer = fullfile(project_root, 'Results', 'reviewer_response_figure_data.xlsx');
assert(numel(sheetnames(paper)) == 14, '正文工作簿不完整。');
expected = ["ADMM_Sensitivity", "BigM_Sensitivity", "UserGroup_Validation", ...
    "Price_Sensitivity", "Forecast_Sensitivity", "PublicTrace_Validation", ...
    "PublishedDCP_Validation"];
assert(all(ismember(expected, string(sheetnames(reviewer)))), '审稿工作簿不完整。');
fprintf('整套算例完成；当前结果位于 %s。\n', fullfile(project_root, 'Results'));
end

function run_one_entry(entry_file)
%RUN_ONE_ENTRY 隔离入口脚本的 clear，避免清除外层运行列表与项目路径。
run(entry_file);
end
