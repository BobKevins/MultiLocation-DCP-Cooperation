function cfg = prepare_case(project_root, output_directory)
%PREPARE_CASE 读取最终版透明输入并生成统一配置结构。
%
% 输入：
%   project_root     - Final_Code_npjRevise 根目录。
%   output_directory - 当前运行入口的独立结果目录。
%
% 输出：
%   cfg            - 集中式与 ADMM 共用的参数、拓扑和验收阈值。

%% ================================== 00 路径与原始数据 ==================================
if nargin < 1 || strlength(string(project_root)) == 0
    project_root = fileparts(fileparts(mfilename('fullpath')));
end
if nargin < 2 || strlength(string(output_directory)) == 0
    output_directory = fullfile(project_root, 'Paper_Case', 'outputs');
end

cfg.root_directory = char(project_root);                                        % 最终版根目录
cfg.output_directory = char(output_directory);                                  % 当前运行结果目录
cfg.input_file = fullfile(cfg.root_directory, ...
    'Input_Data', 'input_parameters.xlsx');                                     % 统一输入工作簿
cfg.io.save_intermediate = true;                                                % 是否保存单次求解 MAT 文件

assert(isfile(cfg.input_file), '缺少输入文件：%s', cfg.input_file);
if ~isfolder(cfg.output_directory)
    mkdir(cfg.output_directory);
end

hours_data = readmatrix(cfg.input_file, 'Sheet', 'Hours');                      % 小时，h
price_data = readmatrix(cfg.input_file, 'Sheet', 'Price_Data');                 % 分地区电价，USD/MWh
pv_data = readmatrix(cfg.input_file, 'Sheet', 'PV_Data');                       % 光伏基准出力，kW
wind_data = readmatrix(cfg.input_file, 'Sheet', 'WT_Data');                     % 风电基准出力，kW
workload_table = readtable(cfg.input_file, 'Sheet', 'Workload_Data', ...
    'VariableNamingRule', 'preserve');                                          % 各 DCP 实际负荷，request/s

%% ================================== 01 系统规模与时序 ==================================
cfg.number_dc = 5;                                                              % DCP 数量
cfg.number_period = 24;                                                         % 调度时段数，h
cfg.hours = hours_data(:, 1)';                                                  % 时段标签，h
cfg.has_energy = logical([1, 1, 1, 0, 0]);                                     % DCP1--3 含本地能源

%% ================================== 02 电价与新能源 ==================================
cfg.price_ele = zeros(cfg.number_dc, cfg.number_period);                        % 购电价格，USD/MWh
cfg.price_ele(1:3, :) = repmat(price_data(:, 2)', 3, 1);
cfg.price_ele(4, :) = price_data(:, 3)';
cfg.price_ele(5, :) = price_data(:, 4)';
cfg.price_tariff = 10 * ones(1, cfg.number_period);                             % 上网电价，USD/MWh

cfg.p_pv_max = zeros(cfg.number_dc, cfg.number_period);                         % 光伏上限，kW
cfg.p_wind_max = zeros(cfg.number_dc, cfg.number_period);                       % 风电上限，kW
cfg.p_pv_max(1, :) = 2.00 * pv_data(:, 2)';
cfg.p_pv_max(2, :) = 0.20 * pv_data(:, 3)';
cfg.p_pv_max(3, :) = 0.20 * pv_data(:, 4)';
cfg.p_wind_max(1, :) = 0.00 * wind_data(:, 2)';
cfg.p_wind_max(2, :) = 1.07 * wind_data(:, 3)';
cfg.p_wind_max(3, :) = 1.27 * wind_data(:, 4)';

%% ================================== 03 碳成本 ==================================
cfg.carbon_emission_intensity = [0.392, 0.392, 0.392, 0.333, 0.194];           % tCO2/MWh
cfg.carbon_price = [20, 20, 20, 15, 30];                                      % USD/tCO2
cfg.carbon_eleprice = cfg.carbon_emission_intensity .* cfg.carbon_price;       % USD/MWh

%% ================================== 04 DCP 工作负载 ==================================
% Workload_Data 已直接保存模型实际使用的 24 h 交互式和批处理负荷。
% 此处不再使用 DCP 规模系数、0.7/0.3 拆分或任何分时调整系数。
required_columns = [{'Hour', 'Workload_Type'}, ...
    arrayfun(@(dc) sprintf('DCP%d', dc), 1:cfg.number_dc, ...
    'UniformOutput', false)];
assert(all(ismember(required_columns, workload_table.Properties.VariableNames)), ...
    'Workload_Data 缺少必要列：Hour、Workload_Type、DCP1--DCP5。');

workload_type = string(workload_table.Workload_Type);
interactive_rows = strcmpi(workload_type, "Interactive");
batch_rows = strcmpi(workload_type, "Batch");
assert(nnz(interactive_rows) == cfg.number_period && ...
    nnz(batch_rows) == cfg.number_period, ...
    'Workload_Data 必须分别包含 24 行 Interactive 和 24 行 Batch 数据。');

[interactive_hours, interactive_order] = sort(workload_table.Hour(interactive_rows));
[batch_hours, batch_order] = sort(workload_table.Hour(batch_rows));
expected_hours = (0:(cfg.number_period - 1))';
assert(isequal(interactive_hours, expected_hours) && ...
    isequal(batch_hours, expected_hours), ...
    'Workload_Data 的两类负荷都必须完整覆盖 Hour=0--23。');

cfg.workload_inter_origin = zeros(cfg.number_dc, cfg.number_period);             % 交互式实际输入，request/s
cfg.workload_batch_origin = zeros(cfg.number_dc, cfg.number_period);             % 批处理实际输入，request/s
for dc = 1:cfg.number_dc
    dcp_column = sprintf('DCP%d', dc);
    interactive_values = workload_table{interactive_rows, dcp_column};
    batch_values = workload_table{batch_rows, dcp_column};
    cfg.workload_inter_origin(dc, :) = interactive_values(interactive_order)';
    cfg.workload_batch_origin(dc, :) = batch_values(batch_order)';
end

%% ================================== 05 服务器与储能 ==================================
cfg.p_idle = 0.2;                                                              % 单台服务器空闲功率，kW
cfg.p_peak = 0.4;                                                              % 单台服务器峰值功率，kW
cfg.processing_speed_server = 50;                                              % 服务率，request/s/server
cfg.number_server = 7500;                                                      % 单 DCP 最大服务器数
cfg.time_tolerance_batch_original = 1;                                         % Stage 1 批处理延时，h
cfg.time_tolerance_inter_original = 0.05;                                      % Stage 1 交互式延时，s
cfg.coefficient_pue = [1.2, 1.1995, 1.2, 1.2, 1.2];                            % PUE

cfg.p_grid_upper = 5e4;                                                        % 电网功率上限，kW
cfg.p_grid_lower = -1e3;                                                       % 电网功率下限，kW
cfg.cost_ess = 1e6;                                                            % 储能吞吐成本，USD/MWh
cfg.e_max = 100;                                                              % 储能容量，kWh
cfg.soc_initial = 0.5 * cfg.e_max;                                             % 初始储能能量，kWh
cfg.eta_charge = 0.95;                                                        % 充电效率
cfg.eta_discharge = 0.95;                                                     % 放电效率
cfg.p_charge_max = 2000;                                                      % 最大充电功率，kW
cfg.p_discharge_max = 2000;                                                   % 最大放电功率，kW

%% ================================== 06 DCP 交互参数 ==================================
cfg.transfer_workload_upper = 1.3e4;                                           % 任务流上限，request/s
cfg.transfer_workload_lower = -1.3e4;                                          % 任务流下限，request/s
cfg.transfer_power_upper = 4e2;                                                % 电力流上限，kW
cfg.transfer_power_lower = -4e2;                                               % 电力流下限，kW
cfg.cost_workload_transfer = ...
    (cfg.p_peak / cfg.processing_speed_server * 0.5) * 2e-2;                  % 任务迁移成本，USD/request
cfg.cost_power_transfer = 1e-3;                                                % 电力传输成本，USD/kW
cfg.migration_ratio_inter = 0.45;                                              % 交互式任务迁移比例
cfg.migration_ratio_batch = 0.45;                                              % 批处理任务迁移比例

%% ================================== 07 正则项与 ADMM ==================================
cfg.regularization.weight = 1e-2;                                              % epsilon：等价最优解选择权重
cfg.regularization.workload_scale = 1.3e4;                                    % 任务标幺基值
cfg.regularization.grid_scale = 5e3;                                           % 电网功率标幺基值

cfg.admm.rho_task = 100;                                                       % 任务流初始罚因子
cfg.admm.rho_power = 10;                                                       % 电力流初始罚因子
cfg.admm.rho_task_min = 1e-10;                                                 % 任务流罚因子下限
cfg.admm.rho_task_max = 100;                                                   % 任务流罚因子上限
cfg.admm.rho_power_min = 1e-10;                                                % 电力流罚因子下限
cfg.admm.rho_power_max = 100;                                                  % 电力流罚因子上限
cfg.admm.max_iteration = 500;                                                  % 最大迭代次数
cfg.admm.absolute_tolerance = 1e-6;                                            % 绝对停止阈值
cfg.admm.relative_tolerance = 1e-5;                                            % 相对停止阈值
cfg.admm.residual_balance_mu = 10;                                             % 残差均衡阈值
cfg.admm.rho_scale = 2;                                                        % 罚因子缩放倍数
cfg.admm.rho_update_period = 5;                                                % 罚因子更新间隔
cfg.admm.verbose = true;                                                       % 是否打印迭代过程

%% ================================== 08 Stage 2 用户响应参数 ==================================
cfg.stage2.inter_delay_set = [0.05, 0.10, 0.15, 0.20, 0.25];                   % 交互式延时候选，s
cfg.stage2.batch_delay_set = [1, 2, 4, 6];                                    % 批处理延时候选，h
cfg.stage2.inconvenience_inter = 0.0035 * ones(cfg.number_dc, 1);              % 交互式不便系数
cfg.stage2.inconvenience_batch = 1e-5 * ones(cfg.number_dc, 1);                % 批处理不便系数
cfg.stage2.gamma_inter_lower_factor = 0.1;                                    % 交互式激励率下限倍数
cfg.stage2.gamma_inter_upper_factor = 2.0;                                    % 交互式激励率上限倍数
cfg.stage2.gamma_batch_lower_factor = 1.0;                                    % 批处理激励率下限倍数
cfg.stage2.gamma_batch_upper_factor = 5.0;                                    % 批处理激励率上限倍数
cfg.stage2.big_m_cost = 200;                                                  % 用户最优性松弛常数，USD
cfg.stage2.big_m_time = 24;                                                   % 固定时间窗口松弛常数，h
cfg.stage2.number_user_group = 2;                                             % 基准代表性用户组数/DCP
cfg.stage2.zero_workload_tolerance = 1e-6;                                   % R2C4 零负载判定阈值

%% ================================== 09 R2C4 可扩展性参数 ==================================
cfg.scalability.user_group_counts = [2, 4, 6, 8, 10];                          % 用户组数量，groups/DCP
cfg.scalability.number_repetitions = 1;                                      % 每种规模运行次数
cfg.scalability.accounting_tolerance = 1e-7;                                % 用户组负荷闭合阈值
cfg.scalability.reference_two_group_cost = 5456.58959568236;                 % 两用户组参考成本，USD
cfg.scalability.reference_cost_tolerance_percent = 0.01;                     % 参考成本允许偏差，%

%% ================================== 10 求解器与验收阈值 ==================================
cfg.solver = sdpsettings('solver', 'gurobi', 'verbose', 0, ...
    'savesolveroutput', 1, ...
    'gurobi.MIPGap', 1e-6, ...
    'gurobi.IntFeasTol', 1e-8, ...
    'gurobi.BarConvTol', 1e-9);

cfg.acceptance.admm_per_dc_percent = 0.1;                                      % ADMM--集中式逐 DCP 阈值，%
cfg.acceptance.refactor_percent = 1.0;                                         % 新旧模型允许变化，%
cfg.baseline.centralized_total = 6432.056694694322687;                         % V6 Stage 1 总成本，USD
cfg.baseline.centralized_per_dc = [ ...
    860.107861863477297; ...
    703.982519652143878; ...
    902.935824876119682; ...
    2080.139163386959808; ...
    1884.891324915623954];                                                     % V6 Stage 1 逐 DCP 成本，USD

cfg.baseline.final_total = 5456.589438258145;                                 % 正式 M5 集中式总成本，USD
cfg.baseline.final_per_dc = [ ...
    701.088276456229; ...
    524.324544824657; ...
    728.106383388210; ...
    1819.712060895470; ...
    1683.358172693580];                                                        % 正式 M5 集中式逐 DCP 成本，USD
cfg.baseline.final_components = struct( ...
    'interaction', 128.547936441960, ...
    'purchase', 4482.598464165660, ...
    'sell', 16.176925706298, ...
    'carbon', 607.320256377371, ...
    'storage', 0, ...
    'payment', 254.299706979454);                                              % 正式 M5 集中式成本分项，USD

%% ================================== 10 链路与索引映射 ==================================
[cfg.links, cfg.map] = create_links_and_maps(cfg);
cfg.number_links = numel(cfg.links);
cfg.link_type = [cfg.links.type]';                                             % 1交互式/2批处理/3电力
cfg.task_link_mask = cfg.link_type <= 2;
cfg.power_link_mask = cfg.link_type == 3;
cfg.flow_scale = ones(cfg.number_links, 1);                                    % ADMM 共识变量标幺基值
cfg.flow_scale(cfg.task_link_mask) = cfg.transfer_workload_upper;
cfg.flow_scale(cfg.power_link_mask) = cfg.transfer_power_upper;

for dc = 1:cfg.number_dc
    cfg.dcp(dc).has_energy = cfg.has_energy(dc);
    cfg.dcp(dc).pue = cfg.coefficient_pue(dc);
    cfg.dcp(dc).price_ele = cfg.price_ele(dc, :);
    cfg.dcp(dc).carbon_eleprice = cfg.carbon_eleprice(dc);
    cfg.dcp(dc).workload_inter_origin = cfg.workload_inter_origin(dc, :);
    cfg.dcp(dc).workload_batch_origin = cfg.workload_batch_origin(dc, :);
    cfg.dcp(dc).p_pv_max = cfg.p_pv_max(dc, :);
    cfg.dcp(dc).p_wind_max = cfg.p_wind_max(dc, :);
end
end

function [links, map] = create_links_and_maps(cfg)
%CREATE_LINKS_AND_MAPS 创建有符号双边流及 DCP--时段索引。

links = struct('i', {}, 'j', {}, 't', {}, 'type', {}, 'idx', {});
link_index = 0;

for i = 1:cfg.number_dc
    for j = (i + 1):cfg.number_dc
        for t = 1:cfg.number_period
            if i <= 3 && j <= 3
                link_index = link_index + 1;
                links(link_index) = make_link(i, j, t, 1, link_index);
            end

            link_index = link_index + 1;
            links(link_index) = make_link(i, j, t, 2, link_index);

            if i <= 3 && j <= 3
                link_index = link_index + 1;
                links(link_index) = make_link(i, j, t, 3, link_index);
            end
        end
    end
end

map.out_links = cell(cfg.number_dc, 1);
map.in_links = cell(cfg.number_dc, 1);
map.out_inter = cell(cfg.number_dc, cfg.number_period);
map.in_inter = cell(cfg.number_dc, cfg.number_period);
map.out_batch = cell(cfg.number_dc, cfg.number_period);
map.in_batch = cell(cfg.number_dc, cfg.number_period);
map.out_power = cell(cfg.number_dc, cfg.number_period);
map.in_power = cell(cfg.number_dc, cfg.number_period);

for ell = 1:numel(links)
    i = links(ell).i;
    j = links(ell).j;
    t = links(ell).t;
    link_type = links(ell).type;
    map.out_links{i}(end + 1) = ell;
    map.in_links{j}(end + 1) = ell;

    if link_type == 1
        map.out_inter{i, t}(end + 1) = ell;
        map.in_inter{j, t}(end + 1) = ell;
    elseif link_type == 2
        map.out_batch{i, t}(end + 1) = ell;
        map.in_batch{j, t}(end + 1) = ell;
    else
        map.out_power{i, t}(end + 1) = ell;
        map.in_power{j, t}(end + 1) = ell;
    end
end
end

function link = make_link(i, j, t, link_type, link_index)
%MAKE_LINK 构造一条有符号双边链路。

link.i = i;
link.j = j;
link.t = t;
link.type = link_type;
link.idx = link_index;
end
