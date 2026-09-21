%% ================================== 00 环境初始化 ==================================
clear;
clc;
close all;
yalmip('clear');
total_timer = tic;

case_directory = fileparts(mfilename('fullpath'));
project_root = fileparts(case_directory);
common_directory = fullfile(project_root, 'Common_Functions');
output_directory = fullfile(case_directory, 'outputs');
original_path = path;
addpath(common_directory);
cleanup_path = onCleanup(@() path(original_path));

assert(exist('yalmip', 'file') == 2, '未找到 YALMIP，请先配置 YALMIP 路径。');
assert(exist('gurobi', 'file') ~= 0, '未找到 Gurobi MATLAB 接口。');

%% ================================== 01 统一输入与参数 ==================================
cfg = prepare_case(project_root, output_directory);
fprintf('最终论文算例：%d 个 DCP、%d 个时段、%d 条交互链路。\n', ...
    cfg.number_dc, cfg.number_period, cfg.number_links);

%% ================================== 02 集中式 Stage 1 ==================================
fprintf('\n================ 集中式 Stage 1 ================\n');
centralized_result = solve_stage1_centralized(cfg);

%% ================================== 03 ADMM Stage 1 ==================================
fprintf('\n================ ADMM Stage 1 ==================\n');
admm_result = solve_stage1_admm(cfg);
assert(admm_result.converged, '主算例 ADMM 未收敛，不能继续生成正式图表。');

%% ================================== 04 Stage 1 对比与验收 ==================================
fprintf('\n================ Stage 1 对比 ==================\n');
stage1_verification = verify_and_export(cfg, centralized_result, admm_result);

%% ================================== 05 完整 Stage 2 ==================================
fprintf('\n================ 完整 Stage 2 ==================\n');
stage2_verification = verify_stage2_user_logic( ...
    cfg, centralized_result, admm_result);

%% ================================== 06 Shapley 利益分配 ==================================
fprintf('\n================ Shapley 利益分配 ==============\n');
shapley_result = solve_paper_shapley( ...
    cfg, stage2_verification.centralized_stage2);

%% ================================== 07 正文比较方法与用户参数场景 ==================================
paper_scenarios = solve_paper_case_scenarios(cfg, stage2_verification, shapley_result);

%% ================================== 08 当前论文图表数据统一导出 ==================================
fprintf('\n================ 论文图表数据导出 ==============\n');
paper_figure_export = export_paper_figure_data( ...
    cfg, centralized_result, admm_result, stage1_verification, ...
    stage2_verification, shapley_result, paper_scenarios);

%% ================================== 09 运行结果保存 ==================================
total_wall_time_seconds = toc(total_timer);
save(fullfile(output_directory, 'paper_case_workspace.mat'), ...
    'cfg', 'centralized_result', 'admm_result', ...
    'stage1_verification', 'stage2_verification', ...
    'shapley_result', 'paper_figure_export', ...
    'paper_scenarios', ...
    'total_wall_time_seconds', '-v7.3');

fprintf('\n论文算例运行结束，总用时 %.2f s。\n', total_wall_time_seconds);
fprintf('结果目录：%s\n', output_directory);
