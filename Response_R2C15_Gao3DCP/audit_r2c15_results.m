function audit = audit_r2c15_results(cfg, stage1_result, ...
        stage2_results, method_name)
%AUDIT_R2C15_RESULTS 核验三 DCP 场景的 Big-M、守恒和禁用交互。

%% ================================== 00 Stage 2 数值检查 ==================================
maximum_workload_error = 0;
maximum_storage_error = 0;
maximum_power_error = 0;
maximum_initial_soc_error = 0;

for dc = 1:cfg.number_dc
    result = stage2_results{dc};
    maximum_workload_error = max(maximum_workload_error, max([ ...
        result.workload_accounting_inter_error, ...
        result.workload_accounting_batch_error]));

    if cfg.dcp(dc).has_energy
        storage_residual = result.soc(2:end) - result.soc(1:end-1) - ...
            cfg.eta_charge * result.p_charge + ...
            result.p_discharge / cfg.eta_discharge;
        power_residual = result.p_grid + result.p_pv + result.p_wind + ...
            result.p_discharge - result.p_charge + ...
            result.net_power_import - result.p_dc_load;
        maximum_storage_error = max(maximum_storage_error, ...
            max(abs(storage_residual)));
        maximum_power_error = max(maximum_power_error, ...
            max(abs(power_residual)));
        maximum_initial_soc_error = max(maximum_initial_soc_error, ...
            abs(result.soc(1) - cfg.soc_initial));
    else
        maximum_power_error = max(maximum_power_error, ...
            max(abs(result.p_grid - result.p_dc_load)));
    end
end

%% ================================== 01 禁用交互检查 ==================================
method_name = upper(string(method_name));
task_flow = stage1_result.consensus_flow(cfg.task_link_mask);
power_flow = stage1_result.consensus_flow(cfg.power_link_mask);
maximum_disabled_flow = 0;
if method_name == "M2" || method_name == "M4"
    maximum_disabled_flow = max(maximum_disabled_flow, max(abs(task_flow)));
end
if method_name == "M2" || method_name == "M3"
    maximum_disabled_flow = max(maximum_disabled_flow, max(abs(power_flow)));
end

%% ================================== 02 成本 Big-M 检查 ==================================
required_big_m_by_dcp = calculate_required_big_m(cfg, stage1_result);
maximum_required_big_m = max(required_big_m_by_dcp);

audit.maximum_workload_error = maximum_workload_error;
audit.maximum_storage_error = maximum_storage_error;
audit.maximum_power_error = maximum_power_error;
audit.maximum_initial_soc_error = maximum_initial_soc_error;
audit.maximum_disabled_flow = maximum_disabled_flow;
audit.required_big_m_by_dcp = required_big_m_by_dcp;
audit.maximum_required_big_m = maximum_required_big_m;
audit.configured_big_m = cfg.stage2.big_m_cost;
audit.big_m_margin = cfg.stage2.big_m_cost - maximum_required_big_m;
audit.big_m_sufficient = audit.big_m_margin >= -1e-9;
end

function required_big_m = calculate_required_big_m(cfg, stage1_result)
%CALCULATE_REQUIRED_BIG_M 计算每个 DCP 的用户最优性 Big-M 下界。

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
                    candidate_bound = ...
                        coefficient_inter * inter_load * ( ...
                        delta_inter(candidate_a)^2 - ...
                        delta_inter(candidate_b)^2) + ...
                        coefficient_batch * batch_load * ( ...
                        delta_batch(candidate_a)^2 - ...
                        delta_batch(candidate_b)^2) - ...
                        gamma_inter * inter_load * inter_difference - ...
                        gamma_batch * batch_load * batch_difference;
                    required_big_m(dc) = max( ...
                        required_big_m(dc), candidate_bound);
                end
            end
        end
    end
end
end

function [inter_group, batch_group] = build_stage2_groups( ...
        cfg, dc, stage1_result)
%BUILD_STAGE2_GROUPS 重建本地保留和迁入两类代表性用户组。

flow = stage1_result.consensus_flow;
incoming_inter = zeros(1, cfg.number_period);
incoming_batch = zeros(1, cfg.number_period);
for t = 1:cfg.number_period
    outgoing_side_inter = flow(cfg.map.out_inter{dc, t});
    outgoing_side_batch = flow(cfg.map.out_batch{dc, t});
    incoming_side_inter = flow(cfg.map.in_inter{dc, t});
    incoming_side_batch = flow(cfg.map.in_batch{dc, t});
    incoming_inter(t) = sum(max(-outgoing_side_inter, 0)) + ...
        sum(max(incoming_side_inter, 0));
    incoming_batch(t) = sum(max(-outgoing_side_batch, 0)) + ...
        sum(max(incoming_side_batch, 0));
end

post_inter = stage1_result.node{dc}.workload_inter;
post_batch = stage1_result.node{dc}.workload_batch0;
inter_group = [max(post_inter - incoming_inter, 0); incoming_inter];
batch_group = [max(post_batch - incoming_batch, 0); incoming_batch];
end
