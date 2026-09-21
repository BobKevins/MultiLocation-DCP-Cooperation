function [results, summary] = solve_all_stage2(cfg, stage1_result, method_name)
%SOLVE_ALL_STAGE2 依次求解五个 DCP 的 Stage 2 并汇总数值状态。

if nargin < 3
    method_name = 'Stage 1';
end

stage_timer = tic;
results = cell(cfg.number_dc, 1);
per_dcp_cost = zeros(cfg.number_dc, 1);
per_dcp_mip_gap = nan(cfg.number_dc, 1);
per_dcp_solver_time = zeros(cfg.number_dc, 1);
solver_status = strings(cfg.number_dc, 1);

for dc = 1:cfg.number_dc
    fprintf('%s -> DCP%d Stage 2...\n', method_name, dc);
    results{dc} = solve_stage2_users(cfg, dc, stage1_result);
    per_dcp_cost(dc) = results{dc}.end_to_end_cost;
    per_dcp_mip_gap(dc) = extract_mip_gap(results{dc}.diagnostics);
    per_dcp_solver_time(dc) = results{dc}.diagnostics.solvertime;
    solver_status(dc) = string(results{dc}.diagnostics.info);
end

summary.total_operating_cost = sum(per_dcp_cost);
summary.per_dcp_cost = per_dcp_cost;
summary.wall_time_seconds = toc(stage_timer);
summary.solver_time_seconds = sum(per_dcp_solver_time);
summary.maximum_single_dcp_mip_gap = max(per_dcp_mip_gap, [], 'omitnan');
if all(isnan(per_dcp_mip_gap))
    summary.maximum_single_dcp_mip_gap = NaN;
end
summary.per_dcp_mip_gap = per_dcp_mip_gap;
summary.solver_status = solver_status;
summary.all_solved = all(cellfun(@(item) item.diagnostics.problem == 0, results));
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
