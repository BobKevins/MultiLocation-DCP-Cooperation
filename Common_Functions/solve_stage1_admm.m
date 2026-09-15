function result = solve_stage1_admm(cfg)
%SOLVE_STAGE1_ADMM 用共识 ADMM 分布式求解五个 DCP 的 Stage 1 模型。

%% ================================== 00 共识变量初始化 ==================================
stage_timer = tic;
number_links = cfg.number_links;
number_dc = cfg.number_dc;
maximum_iteration = cfg.admm.max_iteration;
if isfield(cfg.admm, 'maximum_wall_time_seconds')
    maximum_wall_time_seconds = cfg.admm.maximum_wall_time_seconds;             % 单场景 ADMM 墙钟时间上限，s
else
    maximum_wall_time_seconds = inf;                                            % 兼容未设置时间上限的旧入口
end

consensus_flow = zeros(number_links, 1);                                       % 全局共识流
sender_flow = zeros(number_links, 1);                                          % 小编号端本地副本
receiver_flow = zeros(number_links, 1);                                        % 大编号端本地副本
dual_sender = zeros(number_links, 1);                                          % 小编号端缩放对偶变量
dual_receiver = zeros(number_links, 1);                                        % 大编号端缩放对偶变量
local_flow = cell(number_dc, 1);                                               % 各 DCP 本地流副本

rho = zeros(number_links, 1);                                                  % 逐链路罚因子
rho(cfg.task_link_mask) = cfg.admm.rho_task;
rho(cfg.power_link_mask) = cfg.admm.rho_power;

history = initialize_history(maximum_iteration, number_dc);
final_node = cell(number_dc, 1);
converged = false;
termination_reason = "MaximumIteration";                                      % ADMM 终止原因

%% ================================== 01 ADMM 主循环 ==================================
for iteration = 1:maximum_iteration
    local_physical_cost = zeros(number_dc, 1);
    local_augmented_cost = zeros(number_dc, 1);

    % 五个 DCP 只使用自身参数和相邻链路副本求解本地问题。
    for dc = 1:number_dc
        [local_flow{dc}, local_physical_cost(dc), ...
            local_augmented_cost(dc), final_node{dc}] = solve_local_dcp( ...
            cfg, dc, consensus_flow, dual_sender, dual_receiver, rho);
    end

    previous_consensus = consensus_flow;
    for ell = 1:number_links
        sender_dc = cfg.links(ell).i;
        receiver_dc = cfg.links(ell).j;
        sender_flow(ell) = local_flow{sender_dc}(ell);
        receiver_flow(ell) = local_flow{receiver_dc}(ell);

        consensus_flow(ell) = 0.5 * ( ...
            sender_flow(ell) + cfg.flow_scale(ell) * dual_sender(ell) + ...
            receiver_flow(ell) + cfg.flow_scale(ell) * dual_receiver(ell));
    end

    dual_sender = dual_sender + ...
        (sender_flow - consensus_flow) ./ cfg.flow_scale;
    dual_receiver = dual_receiver + ...
        (receiver_flow - consensus_flow) ./ cfg.flow_scale;

    [residual, tolerance] = calculate_residuals( ...
        cfg, sender_flow, receiver_flow, consensus_flow, previous_consensus, ...
        dual_sender, dual_receiver, rho);

    history.iteration(iteration) = iteration;
    history.physical_cost(iteration) = sum(local_physical_cost);
    history.per_dc_physical_cost(iteration, :) = local_physical_cost';          % [迭代 x DCP] 本地物理成本，USD
    history.augmented_cost(iteration) = sum(local_augmented_cost);
    history.penalty_cost(iteration) = ...
        history.augmented_cost(iteration) - history.physical_cost(iteration);
    history.primal_task(iteration) = residual.primal_task;
    history.dual_task(iteration) = residual.dual_task;
    history.primal_power(iteration) = residual.primal_power;
    history.dual_power(iteration) = residual.dual_power;
    history.primal_tolerance_task(iteration) = tolerance.primal_task;
    history.dual_tolerance_task(iteration) = tolerance.dual_task;
    history.primal_tolerance_power(iteration) = tolerance.primal_power;
    history.dual_tolerance_power(iteration) = tolerance.dual_power;
    history.rho_task(iteration) = rho(find(cfg.task_link_mask, 1));
    history.rho_power(iteration) = rho(find(cfg.power_link_mask, 1));

    if cfg.admm.verbose && (iteration == 1 || mod(iteration, 10) == 0)
        fprintf(['ADMM %4d: cost=%12.6f, r_task=%9.3e/%9.3e, ' ...
            's_task=%9.3e/%9.3e, r_power=%9.3e/%9.3e, s_power=%9.3e/%9.3e\n'], ...
            iteration, history.physical_cost(iteration), ...
            residual.primal_task, tolerance.primal_task, ...
            residual.dual_task, tolerance.dual_task, ...
            residual.primal_power, tolerance.primal_power, ...
            residual.dual_power, tolerance.dual_power);
    end

    task_converged = residual.primal_task <= tolerance.primal_task && ...
        residual.dual_task <= tolerance.dual_task;
    power_converged = residual.primal_power <= tolerance.primal_power && ...
        residual.dual_power <= tolerance.dual_power;
    if task_converged && power_converged
        converged = true;
        termination_reason = "Converged";
        break;
    end

    % 时间上限在一轮五个 DCP 本地问题全部完成后检查，避免保存半轮共识状态。
    if toc(stage_timer) >= maximum_wall_time_seconds
        termination_reason = "TimeLimit";
        fprintf('ADMM 达到单场景时间上限 %.1f s，在第 %d 次完整迭代后停止。\n', ...
            maximum_wall_time_seconds, iteration);
        break;
    end

    if mod(iteration, cfg.admm.rho_update_period) == 0
        [rho, dual_sender, dual_receiver] = update_rho_group( ...
            cfg.task_link_mask, residual.primal_task, residual.dual_task, ...
            rho, dual_sender, dual_receiver, cfg);
        [rho, dual_sender, dual_receiver] = update_rho_group( ...
            cfg.power_link_mask, residual.primal_power, residual.dual_power, ...
            rho, dual_sender, dual_receiver, cfg);
    end
end

%% ================================== 02 结果整理 ==================================
history = trim_history(history, iteration);
result.method = 'ADMM';
result.converged = converged;
result.iterations = iteration;
result.termination_reason = char(termination_reason);
result.maximum_wall_time_seconds = maximum_wall_time_seconds;
result.total_physical_cost = history.physical_cost(end);
result.total_augmented_cost = history.augmented_cost(end);
result.consensus_flow = consensus_flow;
result.per_dc_cost = zeros(number_dc, 1);
result.node = final_node;
result.history = history;
result.links = cfg.links;

for dc = 1:number_dc
    result.per_dc_cost(dc) = final_node{dc}.physical_cost;
end

result.final_primal_residual = hypot( ...
    history.primal_task(end), history.primal_power(end));
result.final_dual_residual = hypot( ...
    history.dual_task(end), history.dual_power(end));
result.wall_time_seconds = toc(stage_timer);

if cfg.io.save_intermediate
    save(fullfile(cfg.output_directory, 'admm_stage1.mat'), 'result', '-v7.3');
end
fprintf('ADMM Stage 1：%d 次迭代，总物理成本 %.9f USD，收敛=%d\n', ...
    result.iterations, result.total_physical_cost, result.converged);
end

function [flow_value, physical_cost, augmented_cost, node_result] = ...
        solve_local_dcp(cfg, dc, consensus_flow, dual_sender, dual_receiver, rho)
%SOLVE_LOCAL_DCP 求解一个 DCP 的本地凸二次规划。

yalmip('clear');
flow = sdpvar(cfg.number_links, 1, 'full');                                    % 本地交互流副本
model = build_stage1_dcp(cfg, dc, flow, true);

% 每个本地子问题对其相邻工作负载链路显式施加 Psi(i,j)+Psi(j,i)=0。
incident_task_links = intersect( ...
    [cfg.map.out_links{dc}, cfg.map.in_links{dc}], find(cfg.task_link_mask));
[skew_constraints, directional_workload_flow] = ...
    add_explicit_skew_symmetry_constraints(cfg, flow, incident_task_links);
constraints = [model.constraints, skew_constraints];

penalty = 0;
for ell = cfg.map.out_links{dc}
    normalized_difference = ...
        (flow(ell) - consensus_flow(ell)) / cfg.flow_scale(ell) + dual_sender(ell);
    penalty = penalty + 0.5 * rho(ell) * normalized_difference^2;
end
for ell = cfg.map.in_links{dc}
    normalized_difference = ...
        (flow(ell) - consensus_flow(ell)) / cfg.flow_scale(ell) + dual_receiver(ell);
    penalty = penalty + 0.5 * rho(ell) * normalized_difference^2;
end

objective = model.objective_physical + model.objective_regularization + penalty;
diagnostics = optimize(constraints, objective, cfg.solver);
if diagnostics.problem ~= 0
    error('DCP%d 本地子问题求解失败：%s', dc, yalmiperror(diagnostics.problem));
end

flow_value = value(flow);
physical_cost = value(model.objective_physical);
augmented_cost = value(objective);
node_result = extract_local_result( ...
    model, flow_value, value(penalty), value(directional_workload_flow));
end

function node_result = extract_local_result( ...
        model, flow_value, penalty_value, directional_workload_flow)
%EXTRACT_LOCAL_RESULT 提取 Workspace 友好的本地数值结构。

node_result.physical_cost = value(model.objective_physical);
node_result.regularization_cost = value(model.objective_regularization);
node_result.penalty_cost = penalty_value;
node_result.cost_purchase = value(model.objective_components.purchase);
node_result.revenue_sell = value(model.objective_components.sell);
node_result.cost_carbon = value(model.objective_components.carbon);
node_result.cost_storage = value(model.objective_components.storage);
node_result.cost_transfer = value(model.objective_components.transfer);
node_result.flow_local = flow_value;
node_result.directional_workload_flow = directional_workload_flow;
node_result.maximum_skew_symmetry_error = max(abs(sum( ...
    directional_workload_flow, 2)));

variable_names = fieldnames(model.variables);
for index = 1:numel(variable_names)
    name = variable_names{index};
    node_result.(name) = value(model.variables.(name));
end
end

function [residual, tolerance] = calculate_residuals( ...
        cfg, sender_flow, receiver_flow, consensus_flow, previous_consensus, ...
        dual_sender, dual_receiver, rho)
%CALCULATE_RESIDUALS 计算任务流与电力流的标准化停止指标。

sender_difference = (sender_flow - consensus_flow) ./ cfg.flow_scale;
receiver_difference = (receiver_flow - consensus_flow) ./ cfg.flow_scale;
consensus_change = (consensus_flow - previous_consensus) ./ cfg.flow_scale;

residual.primal_task = norm([ ...
    sender_difference(cfg.task_link_mask); ...
    receiver_difference(cfg.task_link_mask)]);
residual.dual_task = sqrt(2) * norm( ...
    rho(cfg.task_link_mask) .* consensus_change(cfg.task_link_mask));
residual.primal_power = norm([ ...
    sender_difference(cfg.power_link_mask); ...
    receiver_difference(cfg.power_link_mask)]);
residual.dual_power = sqrt(2) * norm( ...
    rho(cfg.power_link_mask) .* consensus_change(cfg.power_link_mask));

absolute_tolerance = cfg.admm.absolute_tolerance;
relative_tolerance = cfg.admm.relative_tolerance;

tolerance.primal_task = sqrt(2 * nnz(cfg.task_link_mask)) * absolute_tolerance + ...
    relative_tolerance * max(norm([ ...
        sender_flow(cfg.task_link_mask) ./ cfg.flow_scale(cfg.task_link_mask); ...
        receiver_flow(cfg.task_link_mask) ./ cfg.flow_scale(cfg.task_link_mask)]), ...
        sqrt(2) * norm(consensus_flow(cfg.task_link_mask) ./ ...
        cfg.flow_scale(cfg.task_link_mask)));
tolerance.dual_task = sqrt(2 * nnz(cfg.task_link_mask)) * absolute_tolerance + ...
    relative_tolerance * norm([ ...
        rho(cfg.task_link_mask) .* dual_sender(cfg.task_link_mask); ...
        rho(cfg.task_link_mask) .* dual_receiver(cfg.task_link_mask)]);

tolerance.primal_power = sqrt(2 * nnz(cfg.power_link_mask)) * absolute_tolerance + ...
    relative_tolerance * max(norm([ ...
        sender_flow(cfg.power_link_mask) ./ cfg.flow_scale(cfg.power_link_mask); ...
        receiver_flow(cfg.power_link_mask) ./ cfg.flow_scale(cfg.power_link_mask)]), ...
        sqrt(2) * norm(consensus_flow(cfg.power_link_mask) ./ ...
        cfg.flow_scale(cfg.power_link_mask)));
tolerance.dual_power = sqrt(2 * nnz(cfg.power_link_mask)) * absolute_tolerance + ...
    relative_tolerance * norm([ ...
        rho(cfg.power_link_mask) .* dual_sender(cfg.power_link_mask); ...
        rho(cfg.power_link_mask) .* dual_receiver(cfg.power_link_mask)]);
end

function [rho, dual_sender, dual_receiver] = update_rho_group( ...
        group_mask, primal_residual, dual_residual, rho, dual_sender, dual_receiver, cfg)
%UPDATE_RHO_GROUP 按变量类型统一做残差均衡，避免逐链路振荡。

old_rho = rho(find(group_mask, 1));
new_rho = old_rho;

if any(group_mask & cfg.task_link_mask)
    rho_lower = cfg.admm.rho_task_min;
    rho_upper = cfg.admm.rho_task_max;
else
    rho_lower = cfg.admm.rho_power_min;
    rho_upper = cfg.admm.rho_power_max;
end

if primal_residual > cfg.admm.residual_balance_mu * dual_residual
    new_rho = min(cfg.admm.rho_scale * old_rho, rho_upper);
elseif dual_residual > cfg.admm.residual_balance_mu * primal_residual
    new_rho = max(old_rho / cfg.admm.rho_scale, rho_lower);
end

if new_rho ~= old_rho
    dual_scale = old_rho / new_rho;
    rho(group_mask) = new_rho;
    dual_sender(group_mask) = dual_scale * dual_sender(group_mask);
    dual_receiver(group_mask) = dual_scale * dual_receiver(group_mask);
end
end

function history = initialize_history(maximum_iteration, number_dc)
%INITIALIZE_HISTORY 预分配 ADMM 收敛记录。

field_names = { ...
    'iteration', 'physical_cost', 'augmented_cost', 'penalty_cost', ...
    'primal_task', 'dual_task', 'primal_power', 'dual_power', ...
    'primal_tolerance_task', 'dual_tolerance_task', ...
    'primal_tolerance_power', 'dual_tolerance_power', ...
    'rho_task', 'rho_power'};

for index = 1:numel(field_names)
    history.(field_names{index}) = nan(maximum_iteration, 1);
end
history.per_dc_physical_cost = nan(maximum_iteration, number_dc);               % [迭代 x DCP] 本地物理成本，USD
end

function history = trim_history(history, final_iteration)
%TRIM_HISTORY 删除未使用的预分配行。

field_names = fieldnames(history);
for index = 1:numel(field_names)
    name = field_names{index};
    history.(name) = history.(name)(1:final_iteration, :);
end
end
