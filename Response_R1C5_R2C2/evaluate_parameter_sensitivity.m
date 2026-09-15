function [admm_table, big_m_table, details] = evaluate_parameter_sensitivity( ...
        cfg, centralized_stage1, baseline_admm, ...
        baseline_stage2_results, baseline_stage2_summary)
%EVALUATE_PARAMETER_SENSITIVITY 执行 R2-2 的四类单因素敏感性实验。
%
% 罚因子与停止容差只评价 Stage 1 ADMM，并相对集中式 Stage 1 计算成本差距。
% 成本 Big-M 与时间 Big-M 只评价 Stage 2 用户响应 MILP。

centralized_cost = centralized_stage1.total_physical_cost;
baseline_rho_task = cfg.admm.rho_task;
baseline_rho_power = cfg.admm.rho_power;
baseline_absolute_tolerance = cfg.admm.absolute_tolerance;
baseline_relative_tolerance = cfg.admm.relative_tolerance;

%% ================================== 00 初始罚因子敏感性 ==================================
penalty_factors = [0.1, 1, 10];
penalty_runs = cell(numel(penalty_factors), 1);

for index = 1:numel(penalty_factors)
    factor = penalty_factors(index);
    if factor == 1
        penalty_runs{index} = baseline_admm;
        continue;
    end

    cfg_case = cfg;
    cfg_case.io.save_intermediate = false;
    cfg_case.admm.verbose = false;
    cfg_case.admm.rho_task = factor * baseline_rho_task;
    cfg_case.admm.rho_power = factor * baseline_rho_power;
    cfg_case.admm.rho_task_max = max( ...
        cfg.admm.rho_task_max, cfg_case.admm.rho_task);
    cfg_case.admm.rho_power_max = max( ...
        cfg.admm.rho_power_max, cfg_case.admm.rho_power);

    fprintf('\nR2-2 初始罚因子敏感性：%.1f 倍。\n', factor);
    penalty_runs{index} = solve_stage1_admm(cfg_case);
end

%% ================================== 01 停止容差敏感性 ==================================
tolerance_factors = [0.1, 1, 10];
tolerance_runs = cell(numel(tolerance_factors), 1);

for index = 1:numel(tolerance_factors)
    factor = tolerance_factors(index);
    if factor == 1
        tolerance_runs{index} = baseline_admm;
        continue;
    end

    cfg_case = cfg;
    cfg_case.io.save_intermediate = false;
    cfg_case.admm.verbose = false;
    cfg_case.admm.absolute_tolerance = ...
        factor * baseline_absolute_tolerance;
    cfg_case.admm.relative_tolerance = ...
        factor * baseline_relative_tolerance;

    fprintf('\nR2-2 停止容差敏感性：%.1f 倍。\n', factor);
    tolerance_runs{index} = solve_stage1_admm(cfg_case);
end

%% ================================== 02 ADMM Response 表 ==================================
number_admm_rows = numel(penalty_factors) + numel(tolerance_factors);
parameter_type = strings(number_admm_rows, 1);
parameter_setting = strings(number_admm_rows, 1);
multiplier = zeros(number_admm_rows, 1);
rho_task_initial = zeros(number_admm_rows, 1);
rho_power_initial = zeros(number_admm_rows, 1);
absolute_tolerance = zeros(number_admm_rows, 1);
relative_tolerance = zeros(number_admm_rows, 1);
stage1_operating_cost = zeros(number_admm_rows, 1);
relative_gap = zeros(number_admm_rows, 1);
admm_iterations = zeros(number_admm_rows, 1);
admm_converged = false(number_admm_rows, 1);
admm_wall_time = zeros(number_admm_rows, 1);
rho_task_final = zeros(number_admm_rows, 1);
rho_power_final = zeros(number_admm_rows, 1);
final_primal_residual = zeros(number_admm_rows, 1);
final_dual_residual = zeros(number_admm_rows, 1);

for index = 1:numel(penalty_factors)
    row = index;
    factor = penalty_factors(index);
    run = penalty_runs{index};
    parameter_type(row) = "Initial ADMM penalty";
    parameter_setting(row) = sprintf('%.1fx: (%.6g, %.6g)', ...
        factor, factor * baseline_rho_task, factor * baseline_rho_power);
    multiplier(row) = factor;
    rho_task_initial(row) = factor * baseline_rho_task;
    rho_power_initial(row) = factor * baseline_rho_power;
    absolute_tolerance(row) = baseline_absolute_tolerance;
    relative_tolerance(row) = baseline_relative_tolerance;
    stage1_operating_cost(row) = run.total_physical_cost;
    relative_gap(row) = 100 * ...
        (stage1_operating_cost(row) - centralized_cost) / centralized_cost;
    admm_iterations(row) = run.iterations;
    admm_converged(row) = run.converged;
    admm_wall_time(row) = run.wall_time_seconds;
    rho_task_final(row) = run.history.rho_task(end);
    rho_power_final(row) = run.history.rho_power(end);
    final_primal_residual(row) = run.final_primal_residual;
    final_dual_residual(row) = run.final_dual_residual;
end

for index = 1:numel(tolerance_factors)
    row = numel(penalty_factors) + index;
    factor = tolerance_factors(index);
    run = tolerance_runs{index};
    parameter_type(row) = "Convergence tolerance";
    parameter_setting(row) = sprintf( ...
        '%.1fx: abs=%.1e, rel=%.1e', factor, ...
        factor * baseline_absolute_tolerance, ...
        factor * baseline_relative_tolerance);
    multiplier(row) = factor;
    rho_task_initial(row) = baseline_rho_task;
    rho_power_initial(row) = baseline_rho_power;
    absolute_tolerance(row) = factor * baseline_absolute_tolerance;
    relative_tolerance(row) = factor * baseline_relative_tolerance;
    stage1_operating_cost(row) = run.total_physical_cost;
    relative_gap(row) = 100 * ...
        (stage1_operating_cost(row) - centralized_cost) / centralized_cost;
    admm_iterations(row) = run.iterations;
    admm_converged(row) = run.converged;
    admm_wall_time(row) = run.wall_time_seconds;
    rho_task_final(row) = run.history.rho_task(end);
    rho_power_final(row) = run.history.rho_power(end);
    final_primal_residual(row) = run.final_primal_residual;
    final_dual_residual(row) = run.final_dual_residual;
end

admm_table = table( ...
    parameter_type, parameter_setting, multiplier, ...
    rho_task_initial, rho_power_initial, ...
    absolute_tolerance, relative_tolerance, ...
    stage1_operating_cost, relative_gap, admm_iterations, admm_converged, ...
    admm_wall_time, rho_task_final, rho_power_final, ...
    final_primal_residual, final_dual_residual, ...
    'VariableNames', { ...
    'ParameterType', ...
    'ParameterSetting', ...
    'Multiplier', ...
    'InitialRhoTask', ...
    'InitialRhoPower', ...
    'AbsoluteTolerance', ...
    'RelativeTolerance', ...
    'Stage1OperatingCost_USD', ...
    'RelativeGapToCentralizedStage1_Percent', ...
    'ADMMIterations', ...
    'ADMMConverged', ...
    'ADMMWallTime_s', ...
    'FinalRhoTask', ...
    'FinalRhoPower', ...
    'FinalPrimalResidual', ...
    'FinalDualResidual'});

%% ================================== 03 Big-M 敏感性 ==================================
cost_m_factors = [1, 5, 10];
time_m_factors = [1, 5, 10];
number_big_m_rows = numel(cost_m_factors) + numel(time_m_factors);
big_m_type = strings(number_big_m_rows, 1);
big_m_setting = strings(number_big_m_rows, 1);
big_m_multiplier = zeros(number_big_m_rows, 1);
big_m_cost = zeros(number_big_m_rows, 1);
big_m_time = zeros(number_big_m_rows, 1);
interaction_wall_time = zeros(number_big_m_rows, 1);
interaction_solver_time = zeros(number_big_m_rows, 1);
maximum_mip_gap = nan(number_big_m_rows, 1);
solver_status = strings(number_big_m_rows, 1);
stage2_total_cost = zeros(number_big_m_rows, 1);
change_from_baseline = zeros(number_big_m_rows, 1);
big_m_runs = cell(number_big_m_rows, 1);

for index = 1:numel(cost_m_factors)
    row = index;
    factor = cost_m_factors(index);
    cfg_case = cfg;
    cfg_case.io.save_intermediate = false;
    cfg_case.stage2.big_m_cost = factor * cfg.stage2.big_m_cost;

    if factor == 1
        run_results = baseline_stage2_results;
        run_summary = baseline_stage2_summary;
    else
        fprintf('\nR2-2 成本 Big-M 敏感性：%.1f 倍。\n', factor);
        [run_results, run_summary] = solve_all_stage2( ...
            cfg_case, baseline_admm, sprintf('Cost Big-M %.1fx', factor));
    end

    big_m_runs{row}.results = run_results;
    big_m_runs{row}.summary = run_summary;
    big_m_type(row) = "Cost Big-M";
    big_m_setting(row) = sprintf('%.1fx: M_cost=%.6g', ...
        factor, cfg_case.stage2.big_m_cost);
    big_m_multiplier(row) = factor;
    big_m_cost(row) = cfg_case.stage2.big_m_cost;
    big_m_time(row) = cfg_case.stage2.big_m_time;
    interaction_wall_time(row) = run_summary.wall_time_seconds;
    interaction_solver_time(row) = run_summary.solver_time_seconds;
    maximum_mip_gap(row) = run_summary.maximum_single_dcp_mip_gap;
    solver_status(row) = summarize_status(run_summary);
    stage2_total_cost(row) = run_summary.total_operating_cost;
    change_from_baseline(row) = 100 * ...
        (stage2_total_cost(row) - baseline_stage2_summary.total_operating_cost) / ...
        baseline_stage2_summary.total_operating_cost;
end

for index = 1:numel(time_m_factors)
    row = numel(cost_m_factors) + index;
    factor = time_m_factors(index);
    cfg_case = cfg;
    cfg_case.io.save_intermediate = false;
    cfg_case.stage2.big_m_time = factor * cfg.stage2.big_m_time;

    if factor == 1
        run_results = baseline_stage2_results;
        run_summary = baseline_stage2_summary;
    else
        fprintf('\nR2-2 时间 Big-M 敏感性：%.1f 倍。\n', factor);
        [run_results, run_summary] = solve_all_stage2( ...
            cfg_case, baseline_admm, sprintf('Time Big-M %.1fx', factor));
    end

    big_m_runs{row}.results = run_results;
    big_m_runs{row}.summary = run_summary;
    big_m_type(row) = "Time Big-M";
    big_m_setting(row) = sprintf('%.1fx: M_time=%.6g h', ...
        factor, cfg_case.stage2.big_m_time);
    big_m_multiplier(row) = factor;
    big_m_cost(row) = cfg_case.stage2.big_m_cost;
    big_m_time(row) = cfg_case.stage2.big_m_time;
    interaction_wall_time(row) = run_summary.wall_time_seconds;
    interaction_solver_time(row) = run_summary.solver_time_seconds;
    maximum_mip_gap(row) = run_summary.maximum_single_dcp_mip_gap;
    solver_status(row) = summarize_status(run_summary);
    stage2_total_cost(row) = run_summary.total_operating_cost;
    change_from_baseline(row) = 100 * ...
        (stage2_total_cost(row) - baseline_stage2_summary.total_operating_cost) / ...
        baseline_stage2_summary.total_operating_cost;
end

big_m_table = table( ...
    big_m_type, big_m_setting, big_m_multiplier, big_m_cost, big_m_time, ...
    interaction_wall_time, interaction_solver_time, maximum_mip_gap, ...
    solver_status, stage2_total_cost, change_from_baseline, ...
    'VariableNames', { ...
    'ParameterType', ...
    'ParameterSetting', ...
    'Multiplier', ...
    'BigMCost_USD', ...
    'BigMTime_h', ...
    'InteractionWallTime_s', ...
    'InteractionSolverTime_s', ...
    'MaximumSingleDCPMIPGap', ...
    'SolverStatus', ...
    'Stage2EndToEndCost_USD', ...
    'ChangeFromBaseline_Percent'});

%% ================================== 04 完整结果封装 ==================================
details.penalty_runs = penalty_runs;
details.tolerance_runs = tolerance_runs;
details.big_m_runs = big_m_runs;
end

function status = summarize_status(summary)
%SUMMARIZE_STATUS 将五个 DCP 的求解状态压缩为 Response 表格字段。

if summary.all_solved
    status = "Solved";
else
    status = strjoin(unique(summary.solver_status), '; ');
end
end
