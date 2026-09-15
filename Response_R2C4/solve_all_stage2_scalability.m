function [results, summary] = solve_all_stage2_scalability( ...
    cfg, stage1_result, scenario_name)
%SOLVE_ALL_STAGE2_SCALABILITY 求解五个 DCP 并记录 R2C4 计算指标。

if nargin < 3
    scenario_name = sprintf('%d groups/DCP', cfg.stage2.number_user_group);
end

%% ================================== 00 结果容器 ==================================
number_dc = cfg.number_dc;
results = cell(number_dc, 1);
per_dcp_wall_time = zeros(number_dc, 1);                                      % 单 DCP 墙钟时间，s
per_dcp_solver_time = zeros(number_dc, 1);                                    % Gurobi 求解时间，s
per_dcp_mip_gap = nan(number_dc, 1);                                          % Gurobi 最终 MIP gap
per_dcp_cost = zeros(number_dc, 1);                                           % Stage 2 端到端成本，USD
per_dcp_accounting_error = zeros(number_dc, 1);                               % 用户组负载闭合误差
per_dcp_status = strings(number_dc, 1);                                       % 求解器状态
per_dcp_zero_inter_count = zeros(number_dc, 1);                               % 交互式零负载用户--时段数
per_dcp_zero_batch_count = zeros(number_dc, 1);                               % 批处理零负载用户--时段数
per_dcp_active_candidate_count = zeros(number_dc, 1);                         % 预处理后有效候选总数
per_dcp_full_candidate_count = zeros(number_dc, 1);                           % 预处理前候选总数
per_dcp_pairwise_constraint_count = zeros(number_dc, 1);                      % 预处理后成对最优性约束数

%% ================================== 01 五个 DCP 顺序求解 ==================================
total_timer = tic;
for dc = 1:number_dc
    fprintf('%s -> DCP%d Stage 2...\n', scenario_name, dc);
    dcp_timer = tic;
    results{dc} = solve_stage2_users_scalability(cfg, dc, stage1_result);
    per_dcp_wall_time(dc) = toc(dcp_timer);

    per_dcp_solver_time(dc) = results{dc}.diagnostics.solvertime;
    per_dcp_mip_gap(dc) = extract_mip_gap(results{dc}.diagnostics);
    per_dcp_cost(dc) = results{dc}.end_to_end_cost;
    per_dcp_accounting_error(dc) = max([ ...
        results{dc}.workload_accounting_inter_error, ...
        results{dc}.workload_accounting_batch_error]);
    per_dcp_status(dc) = string(results{dc}.diagnostics.info);
    per_dcp_zero_inter_count(dc) = results{dc}.zero_inter_user_period_count;
    per_dcp_zero_batch_count(dc) = results{dc}.zero_batch_user_period_count;
    per_dcp_active_candidate_count(dc) = results{dc}.active_candidate_count;
    per_dcp_full_candidate_count(dc) = results{dc}.full_candidate_count;
    per_dcp_pairwise_constraint_count(dc) = ...
        results{dc}.pairwise_optimality_constraint_count;
end

%% ================================== 02 汇总 ==================================
summary.number_user_group = cfg.stage2.number_user_group;
summary.total_wall_time_seconds = toc(total_timer);
summary.maximum_single_dcp_wall_time_seconds = max(per_dcp_wall_time);
summary.total_solver_time_seconds = sum(per_dcp_solver_time);
summary.maximum_single_dcp_mip_gap = max(per_dcp_mip_gap, [], 'omitnan');
if all(isnan(per_dcp_mip_gap))
    summary.maximum_single_dcp_mip_gap = NaN;
end
summary.total_end_to_end_cost = sum(per_dcp_cost);
summary.maximum_workload_accounting_error = max(per_dcp_accounting_error);
summary.all_solved = all(cellfun(@(item) item.diagnostics.problem == 0, results));
summary.per_dcp_wall_time_seconds = per_dcp_wall_time;
summary.per_dcp_solver_time_seconds = per_dcp_solver_time;
summary.per_dcp_mip_gap = per_dcp_mip_gap;
summary.per_dcp_cost = per_dcp_cost;
summary.per_dcp_accounting_error = per_dcp_accounting_error;
summary.per_dcp_status = per_dcp_status;
summary.per_dcp_zero_inter_count = per_dcp_zero_inter_count;
summary.per_dcp_zero_batch_count = per_dcp_zero_batch_count;
summary.per_dcp_active_candidate_count = per_dcp_active_candidate_count;
summary.per_dcp_full_candidate_count = per_dcp_full_candidate_count;
summary.per_dcp_pairwise_constraint_count = per_dcp_pairwise_constraint_count;
end

function gap = extract_mip_gap(diagnostics)
%EXTRACT_MIP_GAP 兼容提取 Gurobi 返回的 MIP gap。

gap = NaN;
if ~isfield(diagnostics, 'solveroutput') || ...
        ~isstruct(diagnostics.solveroutput)
    return;
end

solver_output = diagnostics.solveroutput;
if isfield(solver_output, 'result') && isstruct(solver_output.result)
    solver_output = solver_output.result;
end

candidate_fields = {'mipgap', 'MIPGap', 'mipGap'};
for index = 1:numel(candidate_fields)
    field_name = candidate_fields{index};
    if isfield(solver_output, field_name)
        gap = solver_output.(field_name);
        return;
    end
end
end
