function cfg = prepare_r2c15_case(project_root, output_directory, method_name)
%PREPARE_R2C15_CASE 构造 Gao published three-node topology 测试配置。

%% ================================== 00 继承五 DCP 正式参数 ==================================
full_cfg = prepare_case(project_root, output_directory);
member_indices = 1:3;
cfg = full_cfg;
cfg.io.save_intermediate = false;
cfg.number_dc = numel(member_indices);
cfg.global_dcp_indices = member_indices;

%% ================================== 01 DCP1--DCP3 参数子集 ==================================
cfg.has_energy = full_cfg.has_energy(member_indices);
cfg.price_ele = full_cfg.price_ele(member_indices, :);
cfg.p_pv_max = full_cfg.p_pv_max(member_indices, :);
cfg.p_wind_max = full_cfg.p_wind_max(member_indices, :);
cfg.carbon_emission_intensity = ...
    full_cfg.carbon_emission_intensity(member_indices);
cfg.carbon_price = full_cfg.carbon_price(member_indices);
cfg.carbon_eleprice = full_cfg.carbon_eleprice(member_indices);
cfg.coefficient_pue = full_cfg.coefficient_pue(member_indices);
cfg.workload_inter_origin = ...
    full_cfg.workload_inter_origin(member_indices, :);
cfg.workload_batch_origin = ...
    full_cfg.workload_batch_origin(member_indices, :);
cfg.dcp = full_cfg.dcp(member_indices);

%% ================================== 02 论文正文 Stage 2 参数 ==================================
cfg.stage2.inter_delay_set = [0.05, 0.10, 0.15, 0.20, 0.25];
cfg.stage2.batch_delay_set = [1, 2, 4, 6];
cfg.stage2.inconvenience_inter = ...
    full_cfg.stage2.inconvenience_inter(member_indices);
cfg.stage2.inconvenience_batch = ...
    full_cfg.stage2.inconvenience_batch(member_indices);
cfg.stage2.big_m_cost = 200;
cfg.stage2.big_m_time = 24;

%% ================================== 03 三节点全连接拓扑 ==================================
topology_file = fullfile(fileparts(mfilename('fullpath')), ...
    'Input_Data', 'gao_3dcp_topology.xlsx');
assert(isfile(topology_file), '缺少 Gao 三节点拓扑输入：%s', topology_file);
link_table = readtable(topology_file, 'Sheet', 'Trading_Links', ...
    'VariableNamingRule', 'preserve');
required_columns = {'From_Node', 'To_Node', 'Interactive_Workload', ...
    'Batch_Workload', 'Electricity'};
assert(all(ismember(required_columns, link_table.Properties.VariableNames)), ...
    'Trading_Links 缺少必要列。');
[cfg.links, cfg.map] = create_gao_links(cfg, link_table);
cfg.number_links = numel(cfg.links);
cfg.link_type = [cfg.links.type]';
cfg.task_link_mask = cfg.link_type <= 2;
cfg.power_link_mask = cfg.link_type == 3;
cfg.flow_scale = ones(cfg.number_links, 1);
cfg.flow_scale(cfg.task_link_mask) = full_cfg.transfer_workload_upper;
cfg.flow_scale(cfg.power_link_mask) = full_cfg.transfer_power_upper;

%% ================================== 04 M2--M5 能力开关 ==================================
method_name = upper(string(method_name));
switch method_name
    case "M2"
        cfg.transfer_workload_lower = 0;
        cfg.transfer_workload_upper = 0;
        cfg.transfer_power_lower = 0;
        cfg.transfer_power_upper = 0;
    case "M3"
        cfg.transfer_power_lower = 0;
        cfg.transfer_power_upper = 0;
    case "M4"
        cfg.transfer_workload_lower = 0;
        cfg.transfer_workload_upper = 0;
    case "M5"
        % 完整保留任务迁移和电力交互。
    otherwise
        error('R2C15 仅支持 M2--M5，当前输入为 %s。', method_name);
end

cfg.response.comment_id = 'R2C15';
cfg.response.method = char(method_name);
cfg.response.topology_source = ...
    'Gao et al., Buildings 2023, 13, 3096';
cfg.response.topology_file = topology_file;
end

function [links, map] = create_gao_links(cfg, link_table)
%CREATE_GAO_LINKS 为每对 DCP 建立 interactive、batch 和 power 链路。

links = struct('i', {}, 'j', {}, 't', {}, 'type', {}, 'idx', {});
link_index = 0;
for row_index = 1:height(link_table)
    i = link_table.From_Node(row_index);
    j = link_table.To_Node(row_index);
    assert(i >= 1 && i < j && j <= cfg.number_dc, ...
        'Trading_Links 第 %d 行节点编号无效。', row_index);
    enabled_type = logical([ ...
        link_table.Interactive_Workload(row_index), ...
        link_table.Batch_Workload(row_index), ...
        link_table.Electricity(row_index)]);
        for t = 1:cfg.number_period
            for link_type = 1:3
                if ~enabled_type(link_type)
                    continue;
                end
                link_index = link_index + 1;
                links(link_index) = struct( ...
                    'i', i, 'j', j, 't', t, ...
                    'type', link_type, 'idx', link_index);
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
    map.out_links{i}(end + 1) = ell;
    map.in_links{j}(end + 1) = ell;
    if links(ell).type == 1
        map.out_inter{i, t}(end + 1) = ell;
        map.in_inter{j, t}(end + 1) = ell;
    elseif links(ell).type == 2
        map.out_batch{i, t}(end + 1) = ell;
        map.in_batch{j, t}(end + 1) = ell;
    else
        map.out_power{i, t}(end + 1) = ell;
        map.in_power{j, t}(end + 1) = ell;
    end
end
end
