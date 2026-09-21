function [inter_group, batch_group, metadata] = build_stage2_user_groups( ...
    cfg, dc, stage1_result)
%BUILD_STAGE2_USER_GROUPS 构造 R2C4 所需的本地与迁入代表性用户组。
%
% 基准的两组分别对应本地保留负载和迁入负载。对于任意偶数组数 N，
% 本函数将两类负载分别等额拆分为 N/2 组，并保持逐时段总负载不变。

%% ================================== 00 规模检查 ==================================
number_user_group = cfg.stage2.number_user_group;                             % 用户组数/DCP
assert(number_user_group >= 2 && mod(number_user_group, 2) == 0, ...
    '代表性用户组数量必须是不小于 2 的偶数，当前值为 %g。', ...
    number_user_group);

number_group_per_origin = number_user_group / 2;                              % 每类用户组数
flow = stage1_result.consensus_flow;                                          % 固定 Stage 1 共识流

%% ================================== 01 本地与迁入负载核算 ==================================
incoming_inter = zeros(1, cfg.number_period);                                 % 迁入交互式负载
incoming_batch = zeros(1, cfg.number_period);                                 % 迁入批处理负载

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

post_inter = stage1_result.node{dc}.workload_inter;                            % 迁移后交互式总负载
post_batch = stage1_result.node{dc}.workload_batch0;                           % 迁移后批处理总负载
local_inter = post_inter - incoming_inter;                                    % 本地保留交互式负载
local_batch = post_batch - incoming_batch;                                    % 本地保留批处理负载

assert(all(local_inter >= -cfg.scalability.accounting_tolerance), ...
    'DCP%d 交互式本地保留负载出现负值，请检查迁移会计。', dc);
assert(all(local_batch >= -cfg.scalability.accounting_tolerance), ...
    'DCP%d 批处理本地保留负载出现负值，请检查迁移会计。', dc);

local_inter = max(local_inter, 0);
local_batch = max(local_batch, 0);

%% ================================== 02 等额扩展用户组 ==================================
inter_group = [ ...
    repmat(local_inter / number_group_per_origin, number_group_per_origin, 1); ...
    repmat(incoming_inter / number_group_per_origin, number_group_per_origin, 1)];
batch_group = [ ...
    repmat(local_batch / number_group_per_origin, number_group_per_origin, 1); ...
    repmat(incoming_batch / number_group_per_origin, number_group_per_origin, 1)];

group_origin = [ ...
    repmat("Local retained", number_group_per_origin, 1); ...
    repmat("Migrated in", number_group_per_origin, 1)];

%% ================================== 03 负载闭合检查 ==================================
inter_accounting_error = max(abs(sum(inter_group, 1) - post_inter));
batch_accounting_error = max(abs(sum(batch_group, 1) - post_batch));

assert(inter_accounting_error <= cfg.scalability.accounting_tolerance, ...
    'DCP%d 交互式用户组负载闭合误差 %.3e 超过阈值。', ...
    dc, inter_accounting_error);
assert(batch_accounting_error <= cfg.scalability.accounting_tolerance, ...
    'DCP%d 批处理用户组负载闭合误差 %.3e 超过阈值。', ...
    dc, batch_accounting_error);

metadata.number_user_group = number_user_group;
metadata.number_group_per_origin = number_group_per_origin;
metadata.group_origin = group_origin;
metadata.inter_accounting_error = inter_accounting_error;
metadata.batch_accounting_error = batch_accounting_error;
end
