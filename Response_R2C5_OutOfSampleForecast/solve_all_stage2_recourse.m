function [results, summary] = solve_all_stage2_recourse( ...
        cfg, realized_stage1_result, day_ahead_stage2_results, method_name)
%SOLVE_ALL_STAGE2_RECOURSE 求解五个 DCP 的 realized local recourse。

stage_timer = tic;
results = cell(cfg.number_dc, 1);
per_dcp_cost = zeros(cfg.number_dc, 1);
per_dcp_mip_gap = nan(cfg.number_dc, 1);
per_dcp_solver_time = zeros(cfg.number_dc, 1);

for dc = 1:cfg.number_dc
    fprintf('%s -> DCP%d realized Stage 2...\n', method_name, dc);
    results{dc} = solve_stage2_recourse(cfg, dc, ...
        realized_stage1_result, day_ahead_stage2_results{dc});
    per_dcp_cost(dc) = results{dc}.end_to_end_cost;
    per_dcp_mip_gap(dc) = extract_mip_gap(results{dc}.diagnostics);
    per_dcp_solver_time(dc) = results{dc}.diagnostics.solvertime;
end

summary.total_operating_cost = sum(per_dcp_cost);
summary.per_dcp_cost = per_dcp_cost;
summary.wall_time_seconds = toc(stage_timer);
summary.solver_time_seconds = sum(per_dcp_solver_time);
summary.maximum_single_dcp_mip_gap = max(per_dcp_mip_gap, [], 'omitnan');
if all(isnan(per_dcp_mip_gap))
    summary.maximum_single_dcp_mip_gap = NaN;
end
summary.total_imbalance_cost = sum(cellfun( ...
    @(item) item.cost_grid_imbalance, results));
summary.maximum_power_balance_error = max(cellfun( ...
    @(item) item.maximum_power_balance_error, results));
summary.all_solved = all(cellfun( ...
    @(item) item.diagnostics.problem == 0, results));
end

function gap = extract_mip_gap(diagnostics)
%EXTRACT_MIP_GAP 兼容提取 Gurobi MIP gap。

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
    if isfield(solver_output, candidate_fields{index})
        gap = solver_output.(candidate_fields{index});
        return;
    end
end
end

