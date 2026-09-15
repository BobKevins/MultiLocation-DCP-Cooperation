function audit_table = audit_r2c11_big_m( ...
        cfg, stage1_result, scenario_name, target_dcp)
%AUDIT_R2C11_BIG_M 核验当前 R2C11 场景的 Stage 2 成本 Big-M。

if nargin < 3
    scenario_name = 'R2C11';
end
if nargin < 4 || isempty(target_dcp)
    target_dcp = 1:cfg.number_dc;
end
target_dcp = target_dcp(:);
assert(all(target_dcp >= 1 & target_dcp <= cfg.number_dc & ...
    target_dcp == round(target_dcp)), '目标 DCP 编号超出有效范围。');

%% ================================== 00 候选延时组合 ==================================
[inter_grid, batch_grid] = ndgrid( ...
    cfg.stage2.inter_delay_set, cfg.stage2.batch_delay_set);
delta_inter = inter_grid(:) - cfg.time_tolerance_inter_original;              % 交互式延时增量，s
delta_batch = batch_grid(:) - cfg.time_tolerance_batch_original;              % 批处理延时增量，h
number_candidate = numel(delta_inter);

%% ================================== 01 目标 DCP 精确边界 ==================================
number_target_dcp = numel(target_dcp);
required_big_m = zeros(number_target_dcp, 1);                                 % 目标 DCP 所需成本 Big-M，USD

for dcp_index = 1:number_target_dcp
    dc = target_dcp(dcp_index);
    [workload_inter, workload_batch] = build_stage2_groups( ...
        cfg, dc, stage1_result);

    coefficient_inter = cfg.stage2.inconvenience_inter(dc);
    coefficient_batch = cfg.stage2.inconvenience_batch(dc);
    gamma_inter_lower = ...
        cfg.stage2.gamma_inter_lower_factor * coefficient_inter;
    gamma_inter_upper = ...
        cfg.stage2.gamma_inter_upper_factor * coefficient_inter;
    gamma_batch_lower = ...
        cfg.stage2.gamma_batch_lower_factor * coefficient_batch;
    gamma_batch_upper = ...
        cfg.stage2.gamma_batch_upper_factor * coefficient_batch;

    for user_group = 1:size(workload_inter, 1)
        for t = 1:cfg.number_period
            inter_load = workload_inter(user_group, t);
            batch_load = workload_batch(user_group, t);

            for candidate_a = 1:number_candidate
                for candidate_b = 1:number_candidate
                    inter_difference = ...
                        delta_inter(candidate_a) - delta_inter(candidate_b);
                    batch_difference = ...
                        delta_batch(candidate_a) - delta_batch(candidate_b);

                    if -inter_load * inter_difference >= 0
                        gamma_inter = gamma_inter_upper;
                    else
                        gamma_inter = gamma_inter_lower;
                    end
                    if -batch_load * batch_difference >= 0
                        gamma_batch = gamma_batch_upper;
                    else
                        gamma_batch = gamma_batch_lower;
                    end

                    candidate_difference = ...
                        coefficient_inter * inter_load * ( ...
                        delta_inter(candidate_a)^2 - delta_inter(candidate_b)^2) + ...
                        coefficient_batch * batch_load * ( ...
                        delta_batch(candidate_a)^2 - delta_batch(candidate_b)^2) - ...
                        gamma_inter * inter_load * inter_difference - ...
                        gamma_batch * batch_load * batch_difference;

                    required_big_m(dcp_index) = max( ...
                        required_big_m(dcp_index), candidate_difference);
                end
            end
        end
    end
end

configured_big_m = repmat(cfg.stage2.big_m_cost, number_target_dcp, 1);
margin = configured_big_m - required_big_m;
is_sufficient = margin >= -1e-9;

audit_table = table( ...
    repmat(string(scenario_name), number_target_dcp, 1), ...
    target_dcp, required_big_m, configured_big_m, margin, is_sufficient, ...
    'VariableNames', { ...
    'Scenario', 'DCP', 'RequiredBigM_USD', 'ConfiguredBigM_USD', ...
    'Margin_USD', 'IsSufficient'});

assert(all(is_sufficient), ...
    ['%s 的 Stage 2 成本 Big-M 不足。最大需求值 %.9f USD，' ...
    '当前配置 %.9f USD。'], ...
    scenario_name, max(required_big_m), cfg.stage2.big_m_cost);
end

function [inter_group, batch_group] = build_stage2_groups(cfg, dc, stage1_result)
%BUILD_STAGE2_GROUPS 按正式 Stage 2 会计口径构造本地保留与迁入两组。

flow = stage1_result.consensus_flow;
incoming_inter = zeros(1, cfg.number_period);
incoming_batch = zeros(1, cfg.number_period);

for t = 1:cfg.number_period
    outgoing_side_inter = flow(cfg.map.out_inter{dc, t});
    outgoing_side_batch = flow(cfg.map.out_batch{dc, t});
    incoming_inter(t) = incoming_inter(t) + sum(max(-outgoing_side_inter, 0));
    incoming_batch(t) = incoming_batch(t) + sum(max(-outgoing_side_batch, 0));

    incoming_side_inter = flow(cfg.map.in_inter{dc, t});
    incoming_side_batch = flow(cfg.map.in_batch{dc, t});
    incoming_inter(t) = incoming_inter(t) + sum(max(incoming_side_inter, 0));
    incoming_batch(t) = incoming_batch(t) + sum(max(incoming_side_batch, 0));
end

post_inter = stage1_result.node{dc}.workload_inter;
post_batch = stage1_result.node{dc}.workload_batch0;
inter_group = [max(post_inter - incoming_inter, 0); incoming_inter];
batch_group = [max(post_batch - incoming_batch, 0); incoming_batch];
end
