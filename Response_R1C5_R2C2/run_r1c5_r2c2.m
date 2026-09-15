%% R1C5 与 R2C2：集中式对比及数值参数敏感性

clear;
clc;
close all;
yalmip('clear');
total_timer = tic;

%% ================================== 00 环境初始化 ==================================
response_directory = fileparts(mfilename('fullpath'));
project_root = fileparts(response_directory);
common_directory = fullfile(project_root, 'Common_Functions');
output_directory = fullfile(response_directory, 'outputs');
original_path = path;
addpath(common_directory, response_directory);
cleanup_path = onCleanup(@() path(original_path));

assert(exist('yalmip', 'file') == 2, '未找到 YALMIP，请先配置 YALMIP 路径。');
assert(exist('gurobi', 'file') ~= 0, '未找到 Gurobi MATLAB 接口。');

%% ================================== 01 集中式与 ADMM Stage 1 ==================================
cfg = prepare_case(project_root, output_directory);

fprintf('\n================ R1C5 集中式 Stage 1 ================\n');
centralized_stage1 = solve_stage1_centralized(cfg);

fprintf('\n================ R1C5 ADMM Stage 1 ==================\n');
proposed_admm = solve_stage1_admm(cfg);
stage1_verification = verify_and_export( ...
    cfg, centralized_stage1, proposed_admm);

%% ================================== 02 基准 Stage 2 ==================================
fprintf('\n================ R2C2 基准 Stage 2 ==================\n');
[baseline_stage2_results, baseline_stage2_summary] = solve_all_stage2( ...
    cfg, proposed_admm, 'Baseline ADMM');

%% ================================== 03 参数敏感性 ==================================
[admm_table, big_m_table, sensitivity_details] = ...
    run_parameter_sensitivity( ...
    cfg, centralized_stage1, proposed_admm, ...
    baseline_stage2_results, baseline_stage2_summary);

%% ================================== 04 结果导出 ==================================
exported = export_response_tables( ...
    cfg, centralized_stage1, proposed_admm, baseline_stage2_summary, ...
    admm_table, big_m_table, sensitivity_details);

total_wall_time_seconds = toc(total_timer);
save(fullfile(output_directory, 'r1c5_r2c2_workspace.mat'), ...
    'cfg', 'centralized_stage1', 'proposed_admm', ...
    'stage1_verification', 'baseline_stage2_results', ...
    'baseline_stage2_summary', 'admm_table', 'big_m_table', ...
    'exported', 'total_wall_time_seconds', '-v7.3');

fprintf('\nR1C5/R2C2 运行结束，总用时 %.2f s。\n', total_wall_time_seconds);
fprintf('结果目录：%s\n', output_directory);
