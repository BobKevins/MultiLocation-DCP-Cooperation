function cfg = prepare_r2c8_case(project_root, output_directory, ...
        price_scaling_factor, method_name)
%PREPARE_R2C8_CASE 构造 R2C8 当地电价敏感性分析配置。
%
% 输入：
%   project_root         - Final_Code_npjRevise 根目录。
%   output_directory     - 当前场景的结果目录。
%   price_scaling_factor - Location 1 电价缩放系数。
%   method_name          - M2 或 M5。
%
% 输出：
%   cfg                 - 继承正式模型后，仅覆盖本审稿意见场景参数的配置。

%% ================================== 00 继承正式版参数 ==================================
cfg = prepare_case(project_root, output_directory);
cfg.io.save_intermediate = false;                                             % 由入口统一保存检查点

%% ================================== 01 论文正文五档/四档参数 ==================================
cfg.stage2.inter_delay_set = [0.05, 0.10, 0.15, 0.20, 0.25];                  % 交互式延时候选，s
cfg.stage2.batch_delay_set = [1, 2, 4, 6];                                    % 批处理延时候选，h
cfg.stage2.big_m_cost = 200;                                                  % 成本 Big-M，USD
cfg.stage2.big_m_time = 24;                                                   % 时间 Big-M，h

%% ================================== 02 Location 1 电价缩放 ==================================
assert(isscalar(price_scaling_factor) && isfinite(price_scaling_factor) && ...
    price_scaling_factor > 0, '电价缩放系数必须为正的有限标量。');

cfg.price_ele(1:3, :) = price_scaling_factor * cfg.price_ele(1:3, :);          % DCP1--3 共用当地电价
for dc = 1:3
    cfg.dcp(dc).price_ele = cfg.price_ele(dc, :);
end

%% ================================== 03 M2/M5 交互能力开关 ==================================
method_name = upper(string(method_name));
switch method_name
    case "M2"
        cfg.transfer_workload_lower = 0;                                      % 禁止任务迁移
        cfg.transfer_workload_upper = 0;
        cfg.transfer_power_lower = 0;                                         % 禁止电力交互
        cfg.transfer_power_upper = 0;
    case "M5"
        % M5 完整保留任务迁移和电力交互。
    otherwise
        error('R2C8 仅支持 M2 和 M5，当前输入为 %s。', method_name);
end

% flow_scale 保留 prepare_case 中的非零标幺基值。关闭交互时只把物理边界置零，
% 避免 epsilon 正则项出现除零，同时不改变原模型的正则化尺度。
cfg.response.comment_id = 'R2C8';
cfg.response.method = char(method_name);
cfg.response.price_scaling_factor = price_scaling_factor;
end
