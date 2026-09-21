function [cfg, generated_workload_table, profile_table] = ...
        prepare_r2c10_case(project_root, output_directory, ...
        validation_directory, trace_name, method_name)
%PREPARE_R2C10_CASE 构造公共 workload trace 交叉验证场景。
%
% 公共数据仅提供 24 h 时间形状。每个 DCP 的 interactive 和 batch 日总量
% 分别保持基准算例不变，从而仅检验时间分布变化对 M2--M5 成本的影响。

%% ================================== 00 继承正式版参数 ==================================
cfg = prepare_case(project_root, output_directory);
cfg.io.save_intermediate = false;                                             % 由入口统一保存检查点

%% ================================== 01 论文正文五档/四档参数 ==================================
cfg.stage2.inter_delay_set = [0.05, 0.10, 0.15, 0.20, 0.25];                  % 交互式延时候选，s
cfg.stage2.batch_delay_set = [1, 2, 4, 6];                                    % 批处理延时候选，h
cfg.stage2.big_m_cost = 220;                                                  % 公共负荷场景成本 Big-M，USD
cfg.stage2.big_m_time = 24;                                                   % 时间 Big-M，h

%% ================================== 02 读取公共 24 h 曲线 ==================================
trace_name = string(trace_name);
switch lower(trace_name)
    case "google"
        profile_sheet = 'Google_Profile';
        trace_name = "Google";
    case "alibaba"
        profile_sheet = 'Alibaba_Profile';
        trace_name = "Alibaba";
    otherwise
        error('R2C10 仅支持 Google 和 Alibaba，当前输入为 %s。', trace_name);
end

profile_file = fullfile(validation_directory, ...
    'Input_Data', 'public_workload_profiles.xlsx');
assert(isfile(profile_file), '缺少公共负荷输入文件：%s', profile_file);

profile_table = readtable(profile_file, 'Sheet', profile_sheet, ...
    'VariableNamingRule', 'preserve');
required_columns = {'Hour', 'Raw_Public_Profile', 'Normalized_Profile'};
assert(all(ismember(required_columns, profile_table.Properties.VariableNames)), ...
    '%s 缺少 Hour、Raw_Public_Profile 或 Normalized_Profile。', profile_sheet);

[sorted_hour, row_order] = sort(profile_table.Hour);
expected_hour = (0:(cfg.number_period - 1))';
assert(isequal(sorted_hour, expected_hour), ...
    '%s 必须完整覆盖 Hour=0--23。', profile_sheet);

profile_table = profile_table(row_order, :);
normalized_profile = profile_table.Normalized_Profile(:)';                    % 公共曲线归一化值
assert(all(isfinite(normalized_profile)) && all(normalized_profile >= 0), ...
    '%s 的归一化曲线包含非法值。', profile_sheet);
assert(sum(normalized_profile) > 0, '%s 的归一化曲线总和必须大于零。', profile_sheet);
profile_weight = normalized_profile / sum(normalized_profile);                % 24 h 日总量分配权重

%% ================================== 03 保持逐 DCP、逐类型日总量 ==================================
baseline_inter_daily_total = sum(cfg.workload_inter_origin, 2);               % 交互式日总量
baseline_batch_daily_total = sum(cfg.workload_batch_origin, 2);               % 批处理日总量

cfg.workload_inter_origin = baseline_inter_daily_total * profile_weight;
cfg.workload_batch_origin = baseline_batch_daily_total * profile_weight;

for dc = 1:cfg.number_dc
    cfg.dcp(dc).workload_inter_origin = cfg.workload_inter_origin(dc, :);
    cfg.dcp(dc).workload_batch_origin = cfg.workload_batch_origin(dc, :);
end

inter_total_error = max(abs( ...
    sum(cfg.workload_inter_origin, 2) - baseline_inter_daily_total));
batch_total_error = max(abs( ...
    sum(cfg.workload_batch_origin, 2) - baseline_batch_daily_total));
assert(inter_total_error <= 1e-7 && batch_total_error <= 1e-7, ...
    '公共负荷归一化未保持逐 DCP、逐类型日总量。');

generated_workload_table = build_generated_workload_table(cfg);

%% ================================== 04 M2--M5 交互能力开关 ==================================
method_name = upper(string(method_name));
switch method_name
    case "M2"
        cfg.transfer_workload_lower = 0;                                      % 禁止任务迁移
        cfg.transfer_workload_upper = 0;
        cfg.transfer_power_lower = 0;                                         % 禁止电力交互
        cfg.transfer_power_upper = 0;
    case "M3"
        cfg.transfer_power_lower = 0;                                         % 仅允许任务迁移
        cfg.transfer_power_upper = 0;
    case "M4"
        cfg.transfer_workload_lower = 0;                                      % 仅允许电力交互
        cfg.transfer_workload_upper = 0;
    case "M5"
        % 完整保留任务迁移和电力交互。
    otherwise
        error('R2C10 仅支持 M2、M3、M4、M5，当前输入为 %s。', method_name);
end

% 关闭交互时仅把物理边界置零。flow_scale 保持正式版非零标幺值，避免正则项除零。
cfg.response.comment_id = 'R2C10';
cfg.response.trace_name = char(trace_name);
cfg.response.method = char(method_name);
cfg.response.profile_file = profile_file;
cfg.response.inter_daily_total_error = inter_total_error;
cfg.response.batch_daily_total_error = batch_total_error;
end

function workload_table = build_generated_workload_table(cfg)
%BUILD_GENERATED_WORKLOAD_TABLE 生成与正式 Workload_Data 一致的透明输入布局。

hour = [(0:(cfg.number_period - 1))'; (0:(cfg.number_period - 1))'];
workload_type = [ ...
    repmat("Interactive", cfg.number_period, 1); ...
    repmat("Batch", cfg.number_period, 1)];
workload_values = [cfg.workload_inter_origin'; cfg.workload_batch_origin'];

workload_table = table(hour, workload_type, ...
    workload_values(:, 1), workload_values(:, 2), workload_values(:, 3), ...
    workload_values(:, 4), workload_values(:, 5), ...
    'VariableNames', { ...
    'Hour', 'Workload_Type', 'DCP1', 'DCP2', 'DCP3', 'DCP4', 'DCP5'});
end
