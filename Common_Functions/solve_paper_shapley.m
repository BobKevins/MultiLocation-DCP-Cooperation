function result = solve_paper_shapley( ...
        cfg, grand_stage1_result, grand_stage2_results)
%SOLVE_PAPER_SHAPLEY 计算正文五个 DCP 的联盟成本与 Shapley 利益分配。
%
% 本函数枚举五个 DCP 的 31 个非空联盟。完整联盟直接复用主入口已经得到的
% 集中式 Stage 1 和 Stage 2 结果，避免重复求解。

%% ================================== 00 基本设置 ==================================
number_player = cfg.number_dc;
number_coalition = 2^number_player;
grand_coalition_mask = number_coalition - 1;

coalition_cost = nan(number_coalition, 1);                                    % 下标=联盟位掩码+1，USD
coalition_cost(1) = 0;
coalition_members = strings(number_coalition, 1);
coalition_members(1) = "Empty";
coalition_size = zeros(number_coalition, 1);
wall_time_seconds = zeros(number_coalition, 1);
maximum_mip_gap = nan(number_coalition, 1);
all_solved = false(number_coalition, 1);
all_solved(1) = true;
grand_coalition_per_dcp_cost = nan(number_player, 1);

%% ================================== 01 联盟成本 ==================================
for coalition_mask = 1:grand_coalition_mask
    members = find(bitget(coalition_mask, 1:number_player));
    member_text = strjoin(string(members), '-');
    coalition_members(coalition_mask + 1) = member_text;
    coalition_size(coalition_mask + 1) = numel(members);

    fprintf('\n================ Coalition {%s} ================\n', member_text);
    coalition_timer = tic;

    if coalition_mask == grand_coalition_mask
        stage1_result = grand_stage1_result;
        stage2_results = grand_stage2_results;
        stage2_summary = summarize_existing_stage2(stage2_results);
    else
        coalition_cfg = build_coalition_cfg(cfg, members);
        stage1_result = solve_stage1_centralized(coalition_cfg);
        [stage2_results, stage2_summary] = solve_all_stage2( ...
            coalition_cfg, stage1_result, "Coalition " + member_text);
    end

    coalition_cost(coalition_mask + 1) = stage2_summary.total_operating_cost;
    wall_time_seconds(coalition_mask + 1) = toc(coalition_timer);
    maximum_mip_gap(coalition_mask + 1) = ...
        stage2_summary.maximum_single_dcp_mip_gap;
    all_solved(coalition_mask + 1) = stage2_summary.all_solved;

    if coalition_mask == grand_coalition_mask
        grand_coalition_per_dcp_cost = stage2_summary.per_dcp_cost;
    end
end

%% ================================== 02 联盟价值 ==================================
independent_cost = zeros(number_player, 1);
for player = 1:number_player
    singleton_mask = bitset(0, player);
    independent_cost(player) = coalition_cost(singleton_mask + 1);
end

coalition_value = zeros(number_coalition, 1);
for coalition_mask = 1:grand_coalition_mask
    members = find(bitget(coalition_mask, 1:number_player));
    coalition_value(coalition_mask + 1) = ...
        sum(independent_cost(members)) - coalition_cost(coalition_mask + 1);
end

%% ================================== 03 Shapley 分配 ==================================
shapley_benefit = zeros(number_player, 1);
factorial_player = factorial(number_player);

for player = 1:number_player
    player_mask = bitset(0, player);

    for subset_mask = 0:grand_coalition_mask
        if bitand(subset_mask, player_mask) ~= 0
            continue;
        end

        subset_size = sum(bitget(subset_mask, 1:number_player));
        coalition_with_player = bitor(subset_mask, player_mask);
        weight = factorial(subset_size) * ...
            factorial(number_player - subset_size - 1) / factorial_player;
        marginal_value = coalition_value(coalition_with_player + 1) - ...
            coalition_value(subset_mask + 1);
        shapley_benefit(player) = shapley_benefit(player) + ...
            weight * marginal_value;
    end
end

final_allocated_cost = independent_cost - shapley_benefit;
grand_coalition_saving = coalition_value(grand_coalition_mask + 1);
efficiency_error = abs(sum(shapley_benefit) - grand_coalition_saving);

assert(all(all_solved), '至少一个 Shapley 联盟算例未正常求解。');
assert(efficiency_error <= 1e-6, ...
    'Shapley 效率性质误差 %.3e USD 超过阈值。', efficiency_error);

%% ================================== 04 结果封装 ==================================
result.coalition_table = table( ...
    (0:grand_coalition_mask)', coalition_members, coalition_size, ...
    coalition_cost, coalition_value, wall_time_seconds, maximum_mip_gap, ...
    all_solved, ...
    'VariableNames', { ...
    'CoalitionMask', 'Members', 'NumberMembers', 'CoalitionCost_USD', ...
    'CoalitionSavingValue_USD', 'WallTime_s', 'MaximumMIPGap', 'AllSolved'});
result.allocation_table = table( ...
    (1:number_player)', independent_cost, grand_coalition_per_dcp_cost, ...
    shapley_benefit, final_allocated_cost, ...
    shapley_benefit ./ independent_cost, ...
    'VariableNames', { ...
    'DCP', 'IndependentCost_USD', 'CooperativeOperationCost_USD', ...
    'ShapleyBenefit_USD', 'FinalAllocatedCost_USD', ...
    'FinalReduction_Ratio'});
result.grand_coalition_saving_usd = grand_coalition_saving;
result.grand_coalition_cost_usd = coalition_cost(grand_coalition_mask + 1);
result.efficiency_error_usd = efficiency_error;
result.all_solved = all(all_solved);

disp(result.allocation_table);
fprintf('Shapley 联盟总节约：%.6f USD。\n', grand_coalition_saving);
end

function summary = summarize_existing_stage2(results)
%SUMMARIZE_EXISTING_STAGE2 汇总主入口已经完成的完整联盟 Stage 2 结果。

number_dcp = numel(results);
per_dcp_cost = zeros(number_dcp, 1);
per_dcp_mip_gap = nan(number_dcp, 1);
all_solved = true;

for dc = 1:number_dcp
    per_dcp_cost(dc) = results{dc}.end_to_end_cost;
    per_dcp_mip_gap(dc) = extract_mip_gap(results{dc}.diagnostics);
    all_solved = all_solved && results{dc}.diagnostics.problem == 0;
end

summary.total_operating_cost = sum(per_dcp_cost);
summary.per_dcp_cost = per_dcp_cost;
summary.maximum_single_dcp_mip_gap = max(per_dcp_mip_gap, [], 'omitnan');
if all(isnan(per_dcp_mip_gap))
    summary.maximum_single_dcp_mip_gap = NaN;
end
summary.all_solved = all_solved;
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

function coalition_cfg = build_coalition_cfg(full_cfg, member_indices)
%BUILD_COALITION_CFG 从正式参数构造指定 DCP 联盟的统一配置。

member_indices = sort(reshape(member_indices, 1, []));
assert(~isempty(member_indices), '联盟不能为空。');
assert(all(member_indices >= 1 & member_indices <= full_cfg.number_dc), ...
    '联盟成员编号超出有效范围。');

coalition_cfg = full_cfg;
coalition_cfg.io.save_intermediate = false;
coalition_cfg.number_dc = numel(member_indices);
coalition_cfg.global_dcp_indices = member_indices;
coalition_cfg.has_energy = full_cfg.has_energy(member_indices);
coalition_cfg.price_ele = full_cfg.price_ele(member_indices, :);
coalition_cfg.p_pv_max = full_cfg.p_pv_max(member_indices, :);
coalition_cfg.p_wind_max = full_cfg.p_wind_max(member_indices, :);
coalition_cfg.carbon_emission_intensity = ...
    full_cfg.carbon_emission_intensity(member_indices);
coalition_cfg.carbon_price = full_cfg.carbon_price(member_indices);
coalition_cfg.carbon_eleprice = full_cfg.carbon_eleprice(member_indices);
coalition_cfg.coefficient_pue = full_cfg.coefficient_pue(member_indices);
coalition_cfg.workload_inter_origin = ...
    full_cfg.workload_inter_origin(member_indices, :);
coalition_cfg.workload_batch_origin = ...
    full_cfg.workload_batch_origin(member_indices, :);
coalition_cfg.stage2.inconvenience_inter = ...
    full_cfg.stage2.inconvenience_inter(member_indices);
coalition_cfg.stage2.inconvenience_batch = ...
    full_cfg.stage2.inconvenience_batch(member_indices);
coalition_cfg.dcp = full_cfg.dcp(member_indices);

[coalition_cfg.links, coalition_cfg.map] = create_coalition_links( ...
    coalition_cfg, member_indices);
coalition_cfg.number_links = numel(coalition_cfg.links);
coalition_cfg.link_type = [coalition_cfg.links.type]';
coalition_cfg.task_link_mask = coalition_cfg.link_type <= 2;
coalition_cfg.power_link_mask = coalition_cfg.link_type == 3;
coalition_cfg.flow_scale = ones(coalition_cfg.number_links, 1);
coalition_cfg.flow_scale(coalition_cfg.task_link_mask) = ...
    coalition_cfg.transfer_workload_upper;
coalition_cfg.flow_scale(coalition_cfg.power_link_mask) = ...
    coalition_cfg.transfer_power_upper;
end

function [links, map] = create_coalition_links(cfg, member_indices)
%CREATE_COALITION_LINKS 创建联盟内部链路与索引映射。

links = struct('i', {}, 'j', {}, 't', {}, 'type', {}, 'idx', {}, ...
    'global_i', {}, 'global_j', {});
link_index = 0;

for local_i = 1:cfg.number_dc
    for local_j = (local_i + 1):cfg.number_dc
        global_i = member_indices(local_i);
        global_j = member_indices(local_j);

        for t = 1:cfg.number_period
            if global_i <= 3 && global_j <= 3
                link_index = link_index + 1;
                links(link_index) = make_link( ...
                    local_i, local_j, global_i, global_j, t, 1, link_index);
            end

            link_index = link_index + 1;
            links(link_index) = make_link( ...
                local_i, local_j, global_i, global_j, t, 2, link_index);

            if cfg.has_energy(local_i) && cfg.has_energy(local_j)
                link_index = link_index + 1;
                links(link_index) = make_link( ...
                    local_i, local_j, global_i, global_j, t, 3, link_index);
            end
        end
    end
end

map.out_links = cell(cfg.number_dc, 1);
map.in_links = cell(cfg.number_dc, 1);
map.out_inter = cell(cfg.number_dc, cfg.number_period);
map.in_inter = cell(cfg.number_dc, cfg.number_period);
map.out_batch = cell(cfg.number_dc, cfg.number_period);
map.in_batch = cell(cfg.number_dc, cfg.number_period);
map.out_power = cell(cfg.number_dc, cfg.number_period);
map.in_power = cell(cfg.number_dc, cfg.number_period);

for ell = 1:numel(links)
    i = links(ell).i;
    j = links(ell).j;
    t = links(ell).t;
    link_type = links(ell).type;
    map.out_links{i}(end + 1) = ell;
    map.in_links{j}(end + 1) = ell;

    if link_type == 1
        map.out_inter{i, t}(end + 1) = ell;
        map.in_inter{j, t}(end + 1) = ell;
    elseif link_type == 2
        map.out_batch{i, t}(end + 1) = ell;
        map.in_batch{j, t}(end + 1) = ell;
    else
        map.out_power{i, t}(end + 1) = ell;
        map.in_power{j, t}(end + 1) = ell;
    end
end
end

function link = make_link(local_i, local_j, global_i, global_j, ...
        t, link_type, link_index)
%MAKE_LINK 保存联盟内部编号与原始 DCP 编号。

link.i = local_i;
link.j = local_j;
link.t = t;
link.type = link_type;
link.idx = link_index;
link.global_i = global_i;
link.global_j = global_j;
end
