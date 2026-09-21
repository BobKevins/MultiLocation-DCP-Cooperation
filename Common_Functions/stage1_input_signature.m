function signature = stage1_input_signature(cfg)
%STAGE1_INPUT_SIGNATURE 标识实际 Stage 1 参数，避免读取不同输入的旧缓存。
% 路径、历史基准和 Stage 2 档位不属于 Stage 1 的运行输入。

payload = cfg;
excluded = {'root_directory', 'output_directory', 'input_file', 'io', ...
    'stage2', 'scalability', 'acceptance', 'baseline', 'response'};
for index = 1:numel(excluded)
    if isfield(payload, excluded{index})
        payload = rmfield(payload, excluded{index});
    end
end
payload = rmfield(payload, 'solver');
payload.stage1_solver_mip_gap = cfg.solver.gurobi.MIPGap;
payload.model_version = 'stage1_v2_live_results_20260915';
signature = jsonencode(payload);
end
