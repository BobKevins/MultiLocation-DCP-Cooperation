function result = solve_stage2_users(cfg, dc, stage1_result)
%SOLVE_STAGE2_USERS 求解单个 DCP 的完整 Stage 2 本地运行模型。
%
% 本函数固定 Stage 1 给出的任务迁移和电力交互结果，联合优化用户延时、
% 批处理时间调整、服务器、IT 功率、本地能源和用户补偿。
%
% 输入：
%   cfg           - prepare_case 生成的统一配置。
%   dc            - DCP 编号。
%   stage1_result - 集中式或 ADMM 的 Stage 1 结果。

%% ================================== 00 两类代表性用户组 ==================================
[workload_inter, workload_batch] = split_representative_groups( ...
    cfg, dc, stage1_result);

number_user_group = 2;                                                         % 1本地保留，2迁入
number_period = cfg.number_period;
inter_delay_set = cfg.stage2.inter_delay_set;                                 % 交互式延时候选，s
batch_delay_set = cfg.stage2.batch_delay_set;                                 % 批处理延时候选，h
[inter_delay_grid, batch_delay_grid] = ndgrid(inter_delay_set, batch_delay_set);
inter_delay_candidate = inter_delay_grid(:);                                   % 组合中的交互式延时，s
batch_delay_candidate = batch_delay_grid(:);                                   % 组合中的批处理延时，h
number_combination = numel(inter_delay_candidate);

delta_inter_candidate = inter_delay_candidate - ...
    cfg.time_tolerance_inter_original;                                         % 交互式延时增量，s
delta_batch_candidate = batch_delay_candidate - ...
    cfg.time_tolerance_batch_original;                                         % 批处理延时增量，h

coefficient_inter = cfg.stage2.inconvenience_inter(dc) * ...
    ones(number_user_group, 1);                                                % 交互式不便系数
coefficient_batch = cfg.stage2.inconvenience_batch(dc) * ...
    ones(number_user_group, 1);                                                % 批处理不便系数
gamma_inter_lower = cfg.stage2.gamma_inter_lower_factor * coefficient_inter;   % 交互式激励率下限
gamma_inter_upper = cfg.stage2.gamma_inter_upper_factor * coefficient_inter;   % 交互式激励率上限
gamma_batch_lower = cfg.stage2.gamma_batch_lower_factor * coefficient_batch;   % 批处理激励率下限
gamma_batch_upper = cfg.stage2.gamma_batch_upper_factor * coefficient_batch;   % 批处理激励率上限

%% ================================== 01 决策变量 ==================================
yalmip('clear');
select_combination = binvar(number_user_group, number_combination, ...
    number_period, 'full');                                                     % 延时组合选择 x(u,k,t)
gamma_inter = sdpvar(number_user_group, number_period, 'full');                 % 交互式激励率 gamma
gamma_batch = sdpvar(number_user_group, number_period, 'full');                 % 批处理激励率 gamma
omega_inter = sdpvar(number_user_group, number_combination, ...
    number_period, 'full');                                                     % gamma_inter * x
omega_batch = sdpvar(number_user_group, number_combination, ...
    number_period, 'full');                                                     % gamma_batch * x
net_cost_candidate = sdpvar(number_user_group, number_combination, ...
    number_period, 'full');                                                     % 各备选组合用户净成本
selected_inter_delay = sdpvar(number_user_group, number_period, 'full');        % 所选交互式延时，s
selected_batch_delay = sdpvar(number_user_group, number_period, 'full');        % 所选批处理延时，h
batch_window_active = binvar(number_user_group, number_period, ...
    number_period, 'full');                                                     % 源--目标时段指示 z(u,t1,t)
delta_batch = sdpvar(number_user_group, number_period, ...
    number_period, 'full');                                                     % 批处理净调整量
adjusted_batch = sdpvar(number_user_group, number_period, 'full');              % 调整后批处理负载
server_inter_group = sdpvar(number_user_group, number_period, 'full');          % 各用户组交互式服务器数
server_batch = sdpvar(1, number_period, 'full');                               % 批处理服务器数
server_total = sdpvar(1, number_period, 'full');                               % 总活跃服务器数
p_it = sdpvar(1, number_period, 'full');                                       % IT 功率，kW
p_dc_load = sdpvar(1, number_period, 'full');                                  % 园区总负载，kW
p_grid = sdpvar(1, number_period, 'full');                                     % 电网净功率，kW
p_grid_buy = sdpvar(1, number_period, 'full');                                 % 购电功率，kW
p_grid_sell = sdpvar(1, number_period, 'full');                                % 售电功率，kW
p_pv = sdpvar(1, number_period, 'full');                                       % 光伏出力，kW
p_wind = sdpvar(1, number_period, 'full');                                     % 风电出力，kW
p_charge = sdpvar(1, number_period, 'full');                                   % 储能充电功率，kW
p_discharge = sdpvar(1, number_period, 'full');                                % 储能放电功率，kW
soc = sdpvar(1, number_period + 1, 'full');                                    % 储能能量，kWh

constraints = [];

%% ================================== 02 档位与精确线性化 ==================================
% omega = gamma * x 使用四组凸包约束精确表示。该部分不依赖集中式结果。
for user_group = 1:number_user_group
    constraints = [constraints, ...
        gamma_inter(user_group, :) >= gamma_inter_lower(user_group), ...
        gamma_inter(user_group, :) <= gamma_inter_upper(user_group), ...
        gamma_batch(user_group, :) >= gamma_batch_lower(user_group), ...
        gamma_batch(user_group, :) <= gamma_batch_upper(user_group)];           %#ok<AGROW>

    for t = 1:number_period
        constraints = [constraints, sum(select_combination(user_group, :, t)) == 1]; %#ok<AGROW>
        constraints = [constraints, ...
            selected_inter_delay(user_group, t) == ...
                select_combination(user_group, :, t) * inter_delay_candidate, ...
            selected_batch_delay(user_group, t) == ...
                select_combination(user_group, :, t) * batch_delay_candidate]; %#ok<AGROW>

        for combination = 1:number_combination
            selected = select_combination(user_group, combination, t);
            omega_i = omega_inter(user_group, combination, t);
            omega_b = omega_batch(user_group, combination, t);
            gamma_i = gamma_inter(user_group, t);
            gamma_b = gamma_batch(user_group, t);

            constraints = [constraints, ...
                omega_i >= gamma_inter_lower(user_group) * selected, ...
                omega_i <= gamma_inter_upper(user_group) * selected, ...
                omega_i >= gamma_i - gamma_inter_upper(user_group) * (1 - selected), ...
                omega_i <= gamma_i - gamma_inter_lower(user_group) * (1 - selected), ...
                omega_b >= gamma_batch_lower(user_group) * selected, ...
                omega_b <= gamma_batch_upper(user_group) * selected, ...
                omega_b >= gamma_b - gamma_batch_upper(user_group) * (1 - selected), ...
                omega_b <= gamma_b - gamma_batch_lower(user_group) * (1 - selected)]; %#ok<AGROW>

            inconvenience = ...
                coefficient_inter(user_group) * workload_inter(user_group, t) * ...
                    delta_inter_candidate(combination)^2 + ...
                coefficient_batch(user_group) * workload_batch(user_group, t) * ...
                    delta_batch_candidate(combination)^2;
            alternative_payment = ...
                gamma_i * delta_inter_candidate(combination) * workload_inter(user_group, t) + ...
                gamma_b * delta_batch_candidate(combination) * workload_batch(user_group, t);
            constraints = [constraints, ...
                net_cost_candidate(user_group, combination, t) == ...
                inconvenience - alternative_payment];                          %#ok<AGROW>
        end
    end
end

%% ================================== 03 用户最优档位 ==================================
big_m_cost = cfg.stage2.big_m_cost;
for user_group = 1:number_user_group
    for t = 1:number_period
        for selected_index = 1:number_combination
            for alternative_index = 1:number_combination
                if selected_index ~= alternative_index
                    constraints = [constraints, ...
                        net_cost_candidate(user_group, selected_index, t) <= ...
                        net_cost_candidate(user_group, alternative_index, t) + ...
                        big_m_cost * (1 - select_combination( ...
                        user_group, selected_index, t))];                       %#ok<AGROW>
                end
            end
        end
    end
end

%% ================================== 04 源--目标批处理窗口 ==================================
% 原时段任务用对角负值表示移出；未来时段只允许非负移入。
% z(u,t1,t) 同时保留源时段和目标时段索引，z=0 时移入量严格为零。
big_m_time = cfg.stage2.big_m_time;                                             % 时间松弛常数，h
for user_group = 1:number_user_group
    for source_time = 1:number_period
        for destination_time = 1:number_period
            if destination_time == source_time
                constraints = [constraints, ...
                    batch_window_active(user_group, source_time, destination_time) == 0, ...
                    delta_batch(user_group, source_time, destination_time) >= ...
                        -workload_batch(user_group, source_time), ...
                    delta_batch(user_group, source_time, destination_time) <= 0]; %#ok<AGROW>
            elseif destination_time > source_time
                active = batch_window_active(user_group, source_time, destination_time);
                shift = delta_batch(user_group, source_time, destination_time);
                constraints = [constraints, ...
                    destination_time <= source_time + ...
                        selected_batch_delay(user_group, source_time) + ...
                        big_m_time * (1 - active), ...
                    shift >= 0, ...
                    shift <= workload_batch(user_group, source_time) * active]; %#ok<AGROW>
            else
                constraints = [constraints, ...
                    batch_window_active(user_group, source_time, destination_time) == 0, ...
                    delta_batch(user_group, source_time, destination_time) == 0]; %#ok<AGROW>
            end
        end
        constraints = [constraints, ...
            sum(delta_batch(user_group, source_time, :), 3) == 0];              %#ok<AGROW>
    end

    for destination_time = 1:number_period
        constraints = [constraints, ...
            adjusted_batch(user_group, destination_time) == ...
            workload_batch(user_group, destination_time) + ...
            sum(delta_batch(user_group, :, destination_time), 2), ...
            adjusted_batch(user_group, destination_time) >= 0];                %#ok<AGROW>
    end
end

%% ================================== 05 用户补偿 ==================================
% 使用 omega 计算所选档位的补偿，目标函数中不再出现 gamma*x 双线性项。
payment_inter = 0;                                                            % 交互式 workload 补偿，USD
payment_batch = 0;                                                            % 批处理 workload 补偿，USD
for user_group = 1:number_user_group
    for t = 1:number_period
        for combination = 1:number_combination
            payment_inter = payment_inter + ...
                omega_inter(user_group, combination, t) * ...
                    delta_inter_candidate(combination) * workload_inter(user_group, t);
            payment_batch = payment_batch + ...
                omega_batch(user_group, combination, t) * ...
                    delta_batch_candidate(combination) * workload_batch(user_group, t);
        end
    end
end
payment = payment_inter + payment_batch;                                      % 两类 workload 总补偿，USD

%% ================================== 06 服务器与 IT 功率 ==================================
% 交互式服务器数在各候选延时下预先计算为常数，保持原版 ceil 处理。
server_inter_candidate = zeros(number_user_group, number_combination, number_period);
for user_group = 1:number_user_group
    for combination = 1:number_combination
        service_margin = cfg.processing_speed_server - ...
            1 / inter_delay_candidate(combination);
        server_inter_candidate(user_group, combination, :) = reshape(ceil( ...
            workload_inter(user_group, :) / service_margin), ...
            1, 1, number_period);
    end
end

for user_group = 1:number_user_group
    for t = 1:number_period
        candidate_servers = reshape( ...
            server_inter_candidate(user_group, :, t), number_combination, 1);
        constraints = [constraints, ...
            server_inter_group(user_group, t) == ...
                select_combination(user_group, :, t) * candidate_servers, ...
            server_inter_group(user_group, t) >= 0, ...
            server_inter_group(user_group, t) <= cfg.number_server];           %#ok<AGROW>
    end
end

for t = 1:number_period
    total_batch_workload = sum(adjusted_batch(:, t));
    total_inter_workload = sum(workload_inter(:, t));
    minimum_batch_servers = total_batch_workload / cfg.processing_speed_server;

    constraints = [constraints, ...
        server_batch(t) >= minimum_batch_servers, ...
        server_batch(t) <= minimum_batch_servers + 1, ...
        server_batch(t) >= 0, ...
        server_batch(t) <= cfg.number_server, ...
        server_total(t) >= sum(server_inter_group(:, t)) + server_batch(t), ...
        server_total(t) >= 0, ...
        server_total(t) <= cfg.number_server];                                 %#ok<AGROW>

    constraints = [constraints, ...
        p_it(t) == cfg.p_idle * server_total(t) + ...
        (cfg.p_peak - cfg.p_idle) / cfg.processing_speed_server * ...
        (total_batch_workload + total_inter_workload), ...
        p_dc_load(t) == cfg.dcp(dc).pue * p_it(t)];                            %#ok<AGROW>
end

%% ================================== 07 本地能源与固定电力交互 ==================================
net_power_import = calculate_net_power_import(cfg, dc, ...
    stage1_result.consensus_flow);                                             % 正值表示净输入，kW

constraints = [constraints, ...
    p_grid_buy >= 0, ...
    p_grid_sell >= 0, ...
    p_grid == p_grid_buy - p_grid_sell, ...
    p_grid >= cfg.p_grid_lower, ...
    p_grid <= cfg.p_grid_upper];

if cfg.dcp(dc).has_energy
    constraints = [constraints, soc(1) == cfg.soc_initial];
    for t = 1:number_period
        constraints = [constraints, ...
            p_pv(t) >= 0, ...
            p_pv(t) <= cfg.dcp(dc).p_pv_max(t), ...
            p_wind(t) >= 0, ...
            p_wind(t) <= cfg.dcp(dc).p_wind_max(t), ...
            p_charge(t) >= 0, ...
            p_charge(t) <= cfg.p_charge_max, ...
            p_discharge(t) >= 0, ...
            p_discharge(t) <= cfg.p_discharge_max, ...
            soc(t + 1) == soc(t) + cfg.eta_charge * p_charge(t) - ...
                p_discharge(t) / cfg.eta_discharge, ...
            soc(t + 1) >= 0, ...
            soc(t + 1) <= cfg.e_max];                                         %#ok<AGROW>

        constraints = [constraints, ...
            p_grid(t) + p_pv(t) + p_wind(t) + p_discharge(t) - p_charge(t) + ...
            net_power_import(t) == p_dc_load(t)];                              %#ok<AGROW>
    end
else
    constraints = [constraints, ...
        p_grid == p_dc_load, ...
        p_pv == 0, ...
        p_wind == 0, ...
        p_charge == 0, ...
        p_discharge == 0, ...
        soc == 0];
end

%% ================================== 08 完整 DCP 目标函数 ==================================
cost_purchase = sum(cfg.dcp(dc).price_ele .* p_grid_buy * 1e-3);
revenue_sell = sum(cfg.price_tariff .* p_grid_sell * 1e-3);
cost_carbon = sum(cfg.dcp(dc).carbon_eleprice * p_grid_buy * 1e-3);
cost_storage = sum(cfg.cost_ess * (p_charge + p_discharge) * 1e-3);
objective_stage2 = cost_purchase - revenue_sell + cost_carbon + ...
    cost_storage + payment;

diagnostics = optimize(constraints, objective_stage2, cfg.solver);
if diagnostics.problem ~= 0
    error('DCP%d Stage 2 完整本地模型求解失败：%s', ...
        dc, yalmiperror(diagnostics.problem));
end

%% ================================== 09 数值结果 ==================================
transfer_cost = calculate_transfer_cost_share(cfg, dc, ...
    stage1_result.consensus_flow);

result.dc = dc;
result.diagnostics = diagnostics;
result.workload_inter_group = workload_inter;
result.workload_batch_group = workload_batch;
result.workload_accounting_inter_error = ...
    max(abs(sum(workload_inter, 1) - stage1_result.node{dc}.workload_inter));
result.workload_accounting_batch_error = ...
    max(abs(sum(workload_batch, 1) - stage1_result.node{dc}.workload_batch0));
result.selected_inter_delay = value(selected_inter_delay);
result.selected_batch_delay = value(selected_batch_delay);
result.adjusted_batch = value(adjusted_batch);
result.gamma_inter = value(gamma_inter);
result.gamma_batch = value(gamma_batch);
result.payment_inter = value(payment_inter);
result.payment_batch = value(payment_batch);
result.payment = value(payment);
result.server_inter_group = value(server_inter_group);
result.server_batch = value(server_batch);
result.server_total = value(server_total);
result.p_it = value(p_it);
result.p_dc_load = value(p_dc_load);
result.p_grid = value(p_grid);
result.p_grid_buy = value(p_grid_buy);
result.p_grid_sell = value(p_grid_sell);
result.p_pv = value(p_pv);
result.p_wind = value(p_wind);
result.p_charge = value(p_charge);
result.p_discharge = value(p_discharge);
result.soc = value(soc);
result.net_power_import = net_power_import;
result.cost_purchase = value(cost_purchase);
result.revenue_sell = value(revenue_sell);
result.cost_carbon = value(cost_carbon);
result.cost_storage = value(cost_storage);
result.stage2_operating_cost = value(objective_stage2);
result.transfer_cost = transfer_cost;
result.end_to_end_cost = result.stage2_operating_cost + transfer_cost;
end

function net_power_import = calculate_net_power_import(cfg, dc, flow)
%CALCULATE_NET_POWER_IMPORT 由 Stage 1 共识流计算固定的净输入电力。

net_power_import = zeros(1, cfg.number_period);
for t = 1:cfg.number_period
    net_power_import(t) = ...
        sum(flow(cfg.map.in_power{dc, t})) - ...
        sum(flow(cfg.map.out_power{dc, t}));
end
end

function transfer_cost = calculate_transfer_cost_share(cfg, dc, flow)
%CALCULATE_TRANSFER_COST_SHARE 按链路两端各 50% 计算 DCP 交互成本。

transfer_cost = 0;
incident_links = [cfg.map.out_links{dc}, cfg.map.in_links{dc}];
for ell = incident_links
    if cfg.links(ell).type <= 2
        unit_cost = cfg.cost_workload_transfer;
    else
        unit_cost = cfg.cost_power_transfer;
    end
    transfer_cost = transfer_cost + 0.5 * unit_cost * abs(flow(ell));
end
end

function [inter_group, batch_group] = split_representative_groups(cfg, dc, stage1_result)
%SPLIT_REPRESENTATIVE_GROUPS 将迁移后负载闭合为本地保留和迁入两组。

flow = stage1_result.consensus_flow;
incoming_inter = zeros(1, cfg.number_period);
incoming_batch = zeros(1, cfg.number_period);

for t = 1:cfg.number_period
    % 对低编号端而言，负流量表示由高编号端迁入。
    outgoing_side_inter = flow(cfg.map.out_inter{dc, t});
    outgoing_side_batch = flow(cfg.map.out_batch{dc, t});
    incoming_inter(t) = incoming_inter(t) + sum(max(-outgoing_side_inter, 0));
    incoming_batch(t) = incoming_batch(t) + sum(max(-outgoing_side_batch, 0));

    % 对高编号端而言，正流量表示由低编号端迁入。
    incoming_side_inter = flow(cfg.map.in_inter{dc, t});
    incoming_side_batch = flow(cfg.map.in_batch{dc, t});
    incoming_inter(t) = incoming_inter(t) + sum(max(incoming_side_inter, 0));
    incoming_batch(t) = incoming_batch(t) + sum(max(incoming_side_batch, 0));
end

post_inter = stage1_result.node{dc}.workload_inter;
post_batch = stage1_result.node{dc}.workload_batch0;
local_inter = post_inter - incoming_inter;
local_batch = post_batch - incoming_batch;

numerical_tolerance = 1e-7;
assert(all(local_inter >= -numerical_tolerance), ...
    'DCP%d 交互式本地保留负载出现负值，请检查迁移会计。', dc);
assert(all(local_batch >= -numerical_tolerance), ...
    'DCP%d 批处理本地保留负载出现负值，请检查迁移会计。', dc);

inter_group = [max(local_inter, 0); incoming_inter];
batch_group = [max(local_batch, 0); incoming_batch];
end
