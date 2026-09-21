function result = solve_stage1_centralized(cfg)
%SOLVE_STAGE1_CENTRALIZED 联合求解五个 DCP 的 Stage 1 基准模型。

%% ================================== 00 建立全局模型 ==================================
stage_timer = tic;
yalmip('clear');
flow = sdpvar(cfg.number_links, 1, 'full');                                    % 全局有符号交互流
constraints = [];
objective_physical = 0;
objective_regularization = 0;
models = cell(cfg.number_dc, 1);

% 显式建立 Psi(i,j)+Psi(j,i)=0；原有 flow 仍是规范有符号流。
[skew_constraints, directional_workload_flow] = ...
    add_explicit_skew_symmetry_constraints(cfg, flow, find(cfg.task_link_mask));
constraints = [constraints, skew_constraints];

for dc = 1:cfg.number_dc
    models{dc} = build_stage1_dcp(cfg, dc, flow, false);
    constraints = [constraints, models{dc}.constraints];                       %#ok<AGROW>
    objective_physical = objective_physical + models{dc}.objective_physical;
    objective_regularization = objective_regularization + ...
        models{dc}.objective_regularization;
end

objective_solver = objective_physical + objective_regularization;

%% ================================== 01 求解 ==================================
diagnostics = optimize(constraints, objective_solver, cfg.solver);
if diagnostics.problem ~= 0
    error('集中式 Stage 1 求解失败：%s', yalmiperror(diagnostics.problem));
end

%% ================================== 02 提取结果 ==================================
result.method = 'Centralized';
result.input_signature = stage1_input_signature(cfg);
result.diagnostics = diagnostics;
result.total_physical_cost = value(objective_physical);
result.regularization_cost = value(objective_regularization);
result.solver_objective = value(objective_solver);
result.consensus_flow = value(flow);
result.links = cfg.links;
result.directional_workload_flow = value(directional_workload_flow);
result.maximum_skew_symmetry_error = max(abs(sum( ...
    result.directional_workload_flow, 2)));
result.wall_time_seconds = toc(stage_timer);
result.node = cell(cfg.number_dc, 1);
result.per_dc_cost = zeros(cfg.number_dc, 1);

for dc = 1:cfg.number_dc
    result.node{dc} = extract_node_result(models{dc});
    result.per_dc_cost(dc) = result.node{dc}.physical_cost;
end

if cfg.io.save_intermediate
    save(fullfile(cfg.output_directory, 'centralized_stage1.mat'), 'result', '-v7.3');
end
fprintf('集中式 Stage 1 总物理成本：%.9f USD\n', result.total_physical_cost);
end

function node_result = extract_node_result(model)
%EXTRACT_NODE_RESULT 将一个 DCP 的 YALMIP 表达式转换为数值结果。

node_result.physical_cost = value(model.objective_physical);
node_result.regularization_cost = value(model.objective_regularization);
node_result.cost_purchase = value(model.objective_components.purchase);
node_result.revenue_sell = value(model.objective_components.sell);
node_result.cost_carbon = value(model.objective_components.carbon);
node_result.cost_storage = value(model.objective_components.storage);
node_result.cost_transfer = value(model.objective_components.transfer);

variable_names = fieldnames(model.variables);
for index = 1:numel(variable_names)
    name = variable_names{index};
    node_result.(name) = value(model.variables.(name));
end
end
