function result = solve_paper_case_scenarios(cfg, stage2_verification, shapley_result)
%SOLVE_PAPER_CASE_SCENARIOS 求解正文 M1--M4 和固定延时 5×4 成本网格。
% 复用完整 Stage 2 模型，不使用论文成本常数，不另建简化比较模型。

%% ================================== 00 独立运行与 M1 ==================================
% 保存本次已完成的联盟计算供中断诊断，不自动复用任何历史计算。
save(fullfile(cfg.output_directory, 'paper_shapley_results.mat'), ...
    'cfg', 'stage2_verification', 'shapley_result', '-v7.3');
independent_input = build_independent_stage1_input(cfg);
result.methods = cell(5, 1);
fixed_cfg = cfg;
fixed_cfg.io.save_intermediate = false;
fixed_cfg.stage2.inter_delay_set = cfg.time_tolerance_inter_original;
fixed_cfg.stage2.batch_delay_set = cfg.time_tolerance_batch_original;
% M1 不进行用户激励；零不便系数使补偿及用户净成本恒为零。
fixed_cfg.stage2.inconvenience_inter(:) = 0;
fixed_cfg.stage2.inconvenience_batch(:) = 0;
[result.methods{1}, ~] = solve_all_stage2(fixed_cfg, independent_input, 'M1');
result.methods{2} = shapley_result.singleton_stage2;
result.methods{5} = stage2_verification.admm_stage2;

%% ================================== 01 M3/M4 继承完整共享模型 ==================================
for method_index = 3:4
    method_cfg = cfg;
    method_cfg.io.save_intermediate = false;
    method_cfg.admm.maximum_wall_time_seconds = 1800;
    if method_index == 3
        method_cfg.transfer_power_lower = 0;
        method_cfg.transfer_power_upper = 0;
    else
        method_cfg.transfer_workload_lower = 0;
        method_cfg.transfer_workload_upper = 0;
    end
    stage1 = solve_stage1_admm(method_cfg);
    assert(stage1.converged, 'M%d ADMM 未收敛：%s。', ...
        method_index, stage1.termination_reason);
    [result.methods{method_index}, ~] = solve_all_stage2( ...
        method_cfg, stage1, sprintf('M%d', method_index));
end

%% ================================== 02 Fig. 7 固定延时物理成本 ==================================
inter_set = cfg.stage2.inter_delay_set;
batch_set = cfg.stage2.batch_delay_set;
result.inter_set = inter_set;
result.batch_set = batch_set;
result.cost_grid = zeros(numel(inter_set), numel(batch_set));
result.grid_results = cell(numel(inter_set), numel(batch_set));
for inter_index = 1:numel(inter_set)
    for batch_index = 1:numel(batch_set)
        grid_cfg = fixed_cfg;
        grid_cfg.stage2.inter_delay_set = inter_set(inter_index);
        grid_cfg.stage2.batch_delay_set = batch_set(batch_index);
        fprintf('Fig. 7：固定交互式 %.2f s、批处理 %.0f h。\n', ...
            inter_set(inter_index), batch_set(batch_index));
        if inter_set(inter_index) == cfg.time_tolerance_inter_original && ...
                batch_set(batch_index) == cfg.time_tolerance_batch_original
            current = result.methods{1}{1};
        else
            current = solve_stage2_users(grid_cfg, 1, independent_input);
        end
        result.grid_results{inter_index, batch_index} = current;
        result.cost_grid(inter_index, batch_index) = current.end_to_end_cost;
    end
end

%% ================================== 03 当前 Fig. 9 求解 ==================================
result.user_sensitivity = solve_paper_user_sensitivity(cfg.root_directory, ...
    fullfile(cfg.root_directory, 'Response_R2C11_Fig9Sensitivity', 'outputs'));
end
