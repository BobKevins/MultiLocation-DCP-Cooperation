function audit_table = audit_r2c5_big_m(cfg, stage1_result, scenario_name)
%AUDIT_R2C5_BIG_M 核验 realized Stage 2 成本 Big-M。

[inter_grid, batch_grid] = ndgrid( ...
    cfg.stage2.inter_delay_set, cfg.stage2.batch_delay_set);
delta_inter = inter_grid(:) - cfg.time_tolerance_inter_original;
delta_batch = batch_grid(:) - cfg.time_tolerance_batch_original;
number_candidate = numel(delta_inter);
required_big_m = zeros(cfg.number_dc, 1);

for dc = 1:cfg.number_dc
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
                        delta_inter(candidate_a)^2 - ...
                        delta_inter(candidate_b)^2) + ...
                        coefficient_batch * batch_load * ( ...
                        delta_batch(candidate_a)^2 - ...
                        delta_batch(candidate_b)^2) - ...
                        gamma_inter * inter_load * inter_difference - ...
                        gamma_batch * batch_load * batch_difference;
                    required_big_m(dc) = max( ...
                        required_big_m(dc), candidate_difference);
                end
            end
        end
    end
end

configured_big_m = repmat(cfg.stage2.big_m_cost, cfg.number_dc, 1);
margin = configured_big_m - required_big_m;
is_sufficient = margin >= -1e-9;
audit_table = table( ...
    repmat(string(scenario_name), cfg.number_dc, 1), ...
    (1:cfg.number_dc)', required_big_m, configured_big_m, margin, ...
    is_sufficient, 'VariableNames', {'Scenario', 'DCP', ...
    'RequiredBigM_USD', 'ConfiguredBigM_USD', 'Margin_USD', ...
    'IsSufficient'});
assert(all(is_sufficient), ...
    '%s 的 Stage 2 成本 Big-M 不充分。', scenario_name);
end

function [inter_group, batch_group] = build_stage2_groups( ...
        cfg, dc, stage1_result)
flow = stage1_result.consensus_flow;
incoming_inter = zeros(1, cfg.number_period);
incoming_batch = zeros(1, cfg.number_period);
for t = 1:cfg.number_period
    outgoing_side_inter = flow(cfg.map.out_inter{dc, t});
    outgoing_side_batch = flow(cfg.map.out_batch{dc, t});
    incoming_inter(t) = incoming_inter(t) + ...
        sum(max(-outgoing_side_inter, 0));
    incoming_batch(t) = incoming_batch(t) + ...
        sum(max(-outgoing_side_batch, 0));
    incoming_side_inter = flow(cfg.map.in_inter{dc, t});
    incoming_side_batch = flow(cfg.map.in_batch{dc, t});
    incoming_inter(t) = incoming_inter(t) + ...
        sum(max(incoming_side_inter, 0));
    incoming_batch(t) = incoming_batch(t) + ...
        sum(max(incoming_side_batch, 0));
end
post_inter = stage1_result.node{dc}.workload_inter;
post_batch = stage1_result.node{dc}.workload_batch0;
inter_group = [max(post_inter - incoming_inter, 0); incoming_inter];
batch_group = [max(post_batch - incoming_batch, 0); incoming_batch];
end

