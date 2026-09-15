function cfg = prepare_r2c5_case(project_root, output_directory, ...
        perturbation_factor, method_name)
%PREPARE_R2C5_CASE 构造 forecast/realized 五 DCP 场景。

%% ================================== 00 继承正式版参数 ==================================
cfg = prepare_case(project_root, output_directory);
cfg.io.save_intermediate = false;

%% ================================== 01 统一论文参数 ==================================
cfg.stage2.inter_delay_set = [0.05, 0.10, 0.15, 0.20, 0.25];                  % 交互式延时候选，s
cfg.stage2.batch_delay_set = [1, 2, 4, 6];                                    % 批处理延时候选，h
cfg.stage2.big_m_cost = 220;                                                   % 成本 Big-M，USD
cfg.stage2.big_m_time = 24;                                                    % 时间 Big-M，h
cfg.response.imbalance_penalty_factor = 0.50;                                 % 购售电偏差价差比例

%% ================================== 02 Forecast perturbation ==================================
assert(isscalar(perturbation_factor) && isfinite(perturbation_factor) && ...
    perturbation_factor > -1 && perturbation_factor < 1, ...
    'Forecast perturbation factor 必须位于 (-1,1)。');

workload_factor = 1 + perturbation_factor;
renewable_factor = 1 - perturbation_factor;

cfg.workload_inter_origin = workload_factor * cfg.workload_inter_origin;
cfg.workload_batch_origin = workload_factor * cfg.workload_batch_origin;
cfg.p_pv_max = renewable_factor * cfg.p_pv_max;
cfg.p_wind_max = renewable_factor * cfg.p_wind_max;

for dc = 1:cfg.number_dc
    cfg.dcp(dc).workload_inter_origin = cfg.workload_inter_origin(dc, :);
    cfg.dcp(dc).workload_batch_origin = cfg.workload_batch_origin(dc, :);
    cfg.dcp(dc).p_pv_max = cfg.p_pv_max(dc, :);
    cfg.dcp(dc).p_wind_max = cfg.p_wind_max(dc, :);
end

%% ================================== 03 M2/M5 开关 ==================================
method_name = upper(string(method_name));
switch method_name
    case "M2"
        cfg.transfer_workload_lower = 0;
        cfg.transfer_workload_upper = 0;
        cfg.transfer_power_lower = 0;
        cfg.transfer_power_upper = 0;
    case "M5"
        % M5 保留任务迁移和电力交互。
    otherwise
        error('R2C5 仅支持 M2 和 M5，当前输入为 %s。', method_name);
end

cfg.response.comment_id = 'R2C5';
cfg.response.method = char(method_name);
cfg.response.perturbation_factor = perturbation_factor;
end
