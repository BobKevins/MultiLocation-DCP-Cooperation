function [realized_result, plan_audit] = build_r2c5_realized_plan( ...
        cfg_realized, day_ahead_result)
%BUILD_R2C5_REALIZED_PLAN 将 day-ahead 共享计划映射到 realized workload。
%
% 电力交易保持原绝对值。任务迁移优先保持原绝对量；仅当源 DCP 的 realized
% workload 不足时，按各接收端的 day-ahead 比例同比缩减。

realized_result = day_ahead_result;
day_ahead_flow = day_ahead_result.consensus_flow;
realized_flow = day_ahead_flow;
number_dc = cfg_realized.number_dc;
number_period = cfg_realized.number_period;

planned_task_export = 0;
realized_task_export = 0;
number_clipped_source_period = 0;

%% ================================== 00 任务迁移可执行化 ==================================
for link_type = 1:2
    if link_type == 1
        source_workload = cfg_realized.workload_inter_origin;
    else
        source_workload = cfg_realized.workload_batch_origin;
    end

    for dc = 1:number_dc
        for t = 1:number_period
            source_links = [];
            for ell = 1:cfg_realized.number_links
                link = cfg_realized.links(ell);
                if link.type ~= link_type || link.t ~= t
                    continue;
                end
                flow_value = day_ahead_flow(ell);
                is_source = (link.i == dc && flow_value > 0) || ...
                    (link.j == dc && flow_value < 0);
                if is_source
                    source_links(end + 1) = ell; %#ok<AGROW>
                end
            end

            if isempty(source_links)
                continue;
            end

            planned_export = sum(abs(day_ahead_flow(source_links)));
            available_workload = source_workload(dc, t);
            scale_factor = min(1, available_workload / max(planned_export, eps));
            realized_flow(source_links) = ...
                scale_factor * day_ahead_flow(source_links);

            planned_task_export = planned_task_export + planned_export;
            realized_task_export = realized_task_export + ...
                sum(abs(realized_flow(source_links)));
            if scale_factor < 1 - 1e-10
                number_clipped_source_period = number_clipped_source_period + 1;
            end
        end
    end
end

%% ================================== 01 重建迁移后负荷 ==================================
realized_result.consensus_flow = realized_flow;
for dc = 1:number_dc
    post_inter = zeros(1, number_period);
    post_batch = zeros(1, number_period);

    for t = 1:number_period
        [out_inter, in_inter] = calculate_physical_flow( ...
            cfg_realized, realized_flow, dc, t, 1);
        [out_batch, in_batch] = calculate_physical_flow( ...
            cfg_realized, realized_flow, dc, t, 2);

        post_inter(t) = cfg_realized.workload_inter_origin(dc, t) - ...
            out_inter + in_inter;
        post_batch(t) = cfg_realized.workload_batch_origin(dc, t) - ...
            out_batch + in_batch;
    end

    assert(all(post_inter >= -1e-7) && all(post_batch >= -1e-7), ...
        'R2C5 realized task-flow mapping produced negative local workload.');
    realized_result.node{dc}.workload_inter = max(post_inter, 0);
    realized_result.node{dc}.workload_batch0 = max(post_batch, 0);
    realized_result.node{dc}.workload_batch = max(post_batch, 0);
end

%% ================================== 02 审计量 ==================================
plan_audit.planned_task_export = planned_task_export;
plan_audit.realized_task_export = realized_task_export;
plan_audit.curtailed_task_export = ...
    planned_task_export - realized_task_export;
plan_audit.number_clipped_source_period = number_clipped_source_period;
plan_audit.maximum_power_plan_deviation = max(abs( ...
    realized_flow(cfg_realized.power_link_mask) - ...
    day_ahead_flow(cfg_realized.power_link_mask)), [], 'omitnan');
if isempty(plan_audit.maximum_power_plan_deviation)
    plan_audit.maximum_power_plan_deviation = 0;
end
end

function [physical_out, physical_in] = calculate_physical_flow( ...
        cfg, flow, dc, t, link_type)
%CALCULATE_PHYSICAL_FLOW 将规范有符号流转换为物理迁出与迁入量。

physical_out = 0;
physical_in = 0;
for ell = 1:cfg.number_links
    link = cfg.links(ell);
    if link.type ~= link_type || link.t ~= t
        continue;
    end

    flow_value = flow(ell);
    if link.i == dc
        physical_out = physical_out + max(flow_value, 0);
        physical_in = physical_in + max(-flow_value, 0);
    elseif link.j == dc
        physical_out = physical_out + max(-flow_value, 0);
        physical_in = physical_in + max(flow_value, 0);
    end
end
end
