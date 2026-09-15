function result = build_independent_stage1_input(cfg)
%BUILD_INDEPENDENT_STAGE1_INPUT 独立运行的零共享输入，不引用旧求解文件。
% 两类迁移及电力交易均不存在，因此无需求解这些恒为零的耦合变量。

result.method = 'Independent, zero sharing';
result.converged = true;
result.consensus_flow = zeros(cfg.number_links, 1);
result.node = cell(cfg.number_dc, 1);
for dc = 1:cfg.number_dc
    result.node{dc}.workload_inter = cfg.workload_inter_origin(dc, :);
    result.node{dc}.workload_batch0 = cfg.workload_batch_origin(dc, :);
end
end
