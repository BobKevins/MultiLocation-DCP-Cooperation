function cfg = prepare_r2c11_case(project_root, output_directory, ...
        sensitivity_type, test_value)
%PREPARE_R2C11_CASE 构造 R2C11 DCP1 单园区敏感性分析配置。
%
% 输入：
%   project_root     - Final_Code_npjRevise 根目录。
%   output_directory - 当前场景输出目录。
%   sensitivity_type - inter_coefficient、batch_coefficient、
%                      inter_delay_max 或 batch_delay_max。
%   test_value       - 系数倍率或最大可选延时。
%
% 输出：
%   cfg               - 继承正式模型后，仅覆盖 R2C11 场景参数的配置。

%% ================================== 00 继承正式版参数 ==================================
cfg = prepare_case(project_root, output_directory);
cfg.io.save_intermediate = false;                                             % 由入口统一保存检查点

%% ================================== 01 当前单园区参数 ==================================
cfg.stage2.inter_delay_set = [0.05, 0.10, 0.15, 0.20, 0.25];                  % 交互式延时候选，s
cfg.stage2.batch_delay_set = [1, 2, 4, 6];                                    % 批处理延时候选，h
cfg.stage2.inconvenience_inter = 0.0035 * ones(cfg.number_dc, 1);              % 当前交互式不便系数基准值
cfg.stage2.inconvenience_batch = 1e-5 * ones(cfg.number_dc, 1);                % 批处理不便系数基准值
cfg.stage2.big_m_cost = 250;                                                  % 覆盖 1.2 倍系数场景，USD
cfg.stage2.big_m_time = 24;                                                   % 时间 Big-M，h

%% ================================== 02 独立敏感性参数 ==================================
sensitivity_type = lower(string(sensitivity_type));
assert(isscalar(test_value) && isfinite(test_value) && test_value > 0, ...
    'R2C11 测试值必须为正的有限标量。');

switch sensitivity_type
    case "inter_coefficient"
        cfg.stage2.inconvenience_inter = test_value * ...
            cfg.stage2.inconvenience_inter;                                   % 仅缩放交互式不便系数
    case "batch_coefficient"
        cfg.stage2.inconvenience_batch = test_value * ...
            cfg.stage2.inconvenience_batch;                                   % 仅缩放批处理不便系数
    case "inter_delay_max"
        assert(any(abs(cfg.stage2.inter_delay_set - test_value) <= 1e-12), ...
            '交互式最大延时必须属于论文正文五档集合。');
        cfg.stage2.inter_delay_set = cfg.stage2.inter_delay_set( ...
            cfg.stage2.inter_delay_set <= test_value + 1e-12);                % 逐步放宽交互式候选上限
    case "batch_delay_max"
        assert(any(abs(cfg.stage2.batch_delay_set - test_value) <= 1e-12), ...
            '批处理最大延时必须属于论文正文四档集合。');
        cfg.stage2.batch_delay_set = cfg.stage2.batch_delay_set( ...
            cfg.stage2.batch_delay_set <= test_value + 1e-12);                % 逐步放宽批处理候选上限
    otherwise
        error('不支持的 R2C11 敏感性类型：%s。', sensitivity_type);
end

cfg.response.comment_id = 'R2C11';
cfg.response.target_dcp = 1;
cfg.response.operation_mode = 'independent_single_dcp';
cfg.response.sensitivity_type = char(sensitivity_type);
cfg.response.test_value = test_value;
end
