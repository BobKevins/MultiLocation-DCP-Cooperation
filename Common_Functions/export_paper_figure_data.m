function export_info = export_paper_figure_data( ...
        cfg, centralized_result, admm_result, stage1_verification, ...
        stage2_verification, shapley_result)
%EXPORT_PAPER_FIGURE_DATA 将论文 Fig. 5--13 和正文结果表整理为 Excel 数据。
%
% 本函数仅进行结果读取、矩阵重排和 Excel 导出，不建立优化变量、不添加约束、
% 不调用求解器。Fig. 10--13 和集中式--ADMM 对比表使用当前主算例结果；
% 其余图表保留已经核对过的论文作图数据布局。

%% ================================== 00 文件路径 ==================================
published_workbook = fullfile(cfg.root_directory, ...
    'Results', 'paper_case_figure_data.xlsx');
figure_workbook = fullfile(cfg.output_directory, ...
    'paper_case_figure_data.xlsx');
assert(isfile(published_workbook), ...
    '缺少公开包正式图表数据：%s', published_workbook);

%% ================================== 01 Fig. 5--6 正式绘图数据 ==================================
% 保留原 Origin 工程使用的列顺序，只移除旧工作表中的计算说明和空白尾行。
figure05_cells = readcell(published_workbook, ...
    'Sheet', 'Fig05_Origin', 'Range', 'A1:F3');
figure06_cells = readcell(published_workbook, ...
    'Sheet', 'Fig06_Origin', 'Range', 'A1:F25');

%% ================================== 02 Fig. 7 三维成本数据 ==================================
% 正式快照已按 Origin XYZ 三列格式保存。
figure07_cells = readcell(published_workbook, ...
    'Sheet', 'Fig07_Origin', 'Range', 'A1:C21');

%% ================================== 03 Fig. 8 延时调节效果 ==================================
% Fig. 8 在原论文中使用独立的敏感性数据块，不能由 Fig. 7 成本矩阵替代。
% Book1 对应 Origin A--G：横坐标加三组“绝对降低量/降低比例”。
% Book2 对应 Origin A--J：保留原工作簿的十列顺序与 [0,2,4,6] 横坐标。
figure08_book1_cells = readcell(published_workbook, ...
    'Sheet', 'Fig08_Book1', 'Range', 'A1:G6');
figure08_book2_cells = readcell(published_workbook, ...
    'Sheet', 'Fig08_Book2', 'Range', 'A1:J5');

%% ================================== 04 Fig. 9 敏感性数据 ==================================
% Fig. 9 使用论文图中的 DCP1 单园区结果，不使用五个 DCP 的汇总成本。
figure09_inter_cells = readcell(published_workbook, ...
    'Sheet', 'Fig09_InterCoeff', 'Range', 'A1:C6');
figure09_batch_cells = readcell(published_workbook, ...
    'Sheet', 'Fig09_BatchCoeff', 'Range', 'A1:C6');
figure09_delay_cells = readcell(published_workbook, ...
    'Sheet', 'Fig09_Delay', 'Range', 'A1:F6');

%% ================================== 05 Fig. 10 DCP 交互数据 ==================================
[figure10_cells, ~] = build_figure10_blocks( ...
    cfg, admm_result.consensus_flow);

%% ================================== 06 Fig. 11 收敛质量数据 ==================================
if isfield(stage1_verification, 'figure11_origin')
    figure11_origin_table = stage1_verification.figure11_origin;
else
    figure11_origin_table = readtable(fullfile(cfg.output_directory, ...
        'figure11_dcp_convergence.csv'), 'VariableNamingRule', 'preserve');
end

%% ================================== 07 Fig. 12--13 成本与利益分配 ==================================
[figure12_cells, figure13_cells] = build_shapley_figure_blocks( ...
    published_workbook, shapley_result);

%% ================================== 08 正文结果表 ==================================
table01_cells = readcell(published_workbook, ...
    'Sheet', 'Table01_Origin', 'Range', 'A1:E8');
table02_cells = build_admm_comparison_block( ...
    centralized_result, admm_result);

%% ================================== 09 Origin 工作簿写入 ==================================
% 完整运行时从 Fig. 5 开始重建工作簿，避免保留上一次运行的旧 Sheet 或旧顺序。
if isfile(figure_workbook)
    delete(figure_workbook);
end

writecell(figure05_cells, figure_workbook, ...
    'Sheet', 'Fig05_Origin', 'WriteMode', 'overwritesheet');
writecell(figure06_cells, figure_workbook, ...
    'Sheet', 'Fig06_Origin', 'WriteMode', 'overwritesheet');
writecell(figure07_cells, figure_workbook, ...
    'Sheet', 'Fig07_Origin', 'WriteMode', 'overwritesheet');
writecell(figure08_book1_cells, figure_workbook, ...
    'Sheet', 'Fig08_Book1', 'WriteMode', 'overwritesheet');
writecell(figure08_book2_cells, figure_workbook, ...
    'Sheet', 'Fig08_Book2', 'WriteMode', 'overwritesheet');
writecell(figure09_inter_cells, figure_workbook, ...
    'Sheet', 'Fig09_InterCoeff', 'WriteMode', 'overwritesheet');
writecell(figure09_batch_cells, figure_workbook, ...
    'Sheet', 'Fig09_BatchCoeff', 'WriteMode', 'overwritesheet');
writecell(figure09_delay_cells, figure_workbook, ...
    'Sheet', 'Fig09_Delay', 'WriteMode', 'overwritesheet');
writecell(figure10_cells, figure_workbook, ...
    'Sheet', 'Fig10_Origin', 'WriteMode', 'overwritesheet');
writetable(figure11_origin_table, figure_workbook, ...
    'Sheet', 'Fig11_Origin', 'WriteMode', 'overwritesheet');
writecell(figure12_cells, figure_workbook, ...
    'Sheet', 'Fig12_Origin', 'WriteMode', 'overwritesheet');
writecell(figure13_cells, figure_workbook, ...
    'Sheet', 'Fig13_Origin', 'WriteMode', 'overwritesheet');
writecell(table01_cells, figure_workbook, ...
    'Sheet', 'Table01_Origin', 'WriteMode', 'overwritesheet');
writecell(table02_cells, figure_workbook, ...
    'Sheet', 'Table02_ADMM', 'WriteMode', 'overwritesheet');

%% ================================== 10 导出检查与结果封装 ==================================
assert(size(figure06_cells, 1) == cfg.number_period + 1, ...
    'Fig. 6 数据必须包含表头和24个时段。');
assert(size(figure10_cells, 1) == 41 && ...
    size(figure10_cells, 2) == cfg.number_period, ...
    'Fig. 10 Origin 数据必须保持 41 x 24 布局。');
assert(height(figure11_origin_table) == admm_result.iterations, ...
    'Fig. 11 数据行数与 ADMM 迭代次数不一致。');
independent_cost = cell2mat(figure12_cells(2, 2:6));
allocated_benefit = cell2mat(figure12_cells(4, 2:6));
final_allocated_cost = cell2mat(figure12_cells(5, 2:6));
assert(abs(sum(allocated_benefit) - ...
    (sum(independent_cost) - sum(final_allocated_cost))) <= 1e-6, ...
    'Fig. 12 Shapley 分配数据未满足效率性质。');
figure13_values = cell2mat(figure13_cells(2:4, 2:7));
figure13_sum_error = abs(sum(figure13_values(:, 1:5), 2) - ...
    figure13_values(:, 6));
assert(all(figure13_sum_error <= 1e-6), ...
    'Fig. 13 各 DCP 成本之和与 Overall 不一致。');
table01_components = cell2mat(table01_cells(2:5, 2:5));
table01_total = cell2mat(table01_cells(6, 2:5));
assert(max(abs(sum(table01_components, 1) - table01_total)) <= 1e-6, ...
    '表1成本分项之和与总成本不一致。');

export_info.workbook = figure_workbook;
export_info.sheet_names = sheetnames(figure_workbook);
export_info.stage2_total_admm_cost_usd = ...
    sum(cellfun(@(item) item.end_to_end_cost, ...
    stage2_verification.admm_stage2));

fprintf('论文 Fig. 5--13 与正文结果表已统一写入：%s\n', figure_workbook);
end

function [figure12_cells, figure13_cells] = build_shapley_figure_blocks( ...
        published_workbook, shapley_result)
%BUILD_SHAPLEY_FIGURE_BLOCKS 由当前联盟求解结果生成 Fig. 12--13 数据。

allocation = shapley_result.allocation_table;
independent_cost = allocation.IndependentCost_USD';
cooperative_cost = allocation.CooperativeOperationCost_USD';
allocated_benefit = allocation.ShapleyBenefit_USD';
final_allocated_cost = allocation.FinalAllocatedCost_USD';
reduction_ratio = allocation.FinalReduction_Ratio';

figure12_cells = cell(7, 7);
figure12_cells(1, :) = { ...
    'Metric', 'DCP1', 'DCP2', 'DCP3', 'DCP4', 'DCP5', 'Overall'};
figure12_cells(2, :) = [{'IndependentCost_USD'}, num2cell(independent_cost), ...
    {sum(independent_cost)}];
figure12_cells(3, :) = [{'CooperativeOperationCost_USD'}, ...
    num2cell(cooperative_cost), {sum(cooperative_cost)}];
figure12_cells(4, :) = [{'AllocatedBenefit_USD'}, ...
    num2cell(allocated_benefit), {sum(allocated_benefit)}];
figure12_cells(5, :) = [{'FinalAllocatedCost_USD'}, ...
    num2cell(final_allocated_cost), {sum(final_allocated_cost)}];
figure12_cells(7, :) = [{'FinalReduction_Ratio'}, ...
    num2cell(reduction_ratio), ...
    {sum(allocated_benefit) / sum(independent_cost)}];

% M1 不受 Shapley 分配影响，保留已核对的正文基准；M2 与 M5 由当前结果生成。
published_figure13 = readcell(published_workbook, ...
    'Sheet', 'Fig13_Origin', 'Range', 'A1:G4');
figure13_cells = cell(4, 7);
figure13_cells(1, :) = published_figure13(1, :);
figure13_cells(2, :) = published_figure13(2, :);
figure13_cells(3, :) = [{'M2'}, num2cell(independent_cost), ...
    {sum(independent_cost)}];
figure13_cells(4, :) = [{'M5'}, num2cell(final_allocated_cost), ...
    {sum(final_allocated_cost)}];
end

function table_cells = build_admm_comparison_block( ...
        centralized_result, admm_result)
%BUILD_ADMM_COMPARISON_BLOCK 生成正文集中式--ADMM 对比表。

relative_difference = 100 * abs( ...
    admm_result.total_physical_cost - centralized_result.total_physical_cost) / ...
    abs(centralized_result.total_physical_cost);
table_cells = { ...
    'Method', 'Stage1OperatingCost_USD', ...
        'RelativeDifference_Percent', 'ADMMIterations'; ...
    'Centralized benchmark', centralized_result.total_physical_cost, ...
        NaN, NaN; ...
    'Distributed ADMM', admm_result.total_physical_cost, ...
        relative_difference, admm_result.iterations};
end

function [origin_cells, audit_table] = build_figure10_blocks(cfg, flow)
%BUILD_FIGURE10_BLOCKS 生成与现有 Origin 工程一致的 41 x 24 交互矩阵。

number_dc = cfg.number_dc;
number_period = cfg.number_period;
workload_flow = zeros(number_dc, number_dc, number_period);                    % 接收为正、送出为负，request/s
power_flow = zeros(number_dc, number_dc, number_period);                       % 接收为正、送出为负，kW

for ell = 1:cfg.number_links
    link = cfg.links(ell);
    if link.type <= 2
        workload_flow(link.i, link.j, link.t) = ...
            workload_flow(link.i, link.j, link.t) - flow(ell);
        workload_flow(link.j, link.i, link.t) = ...
            workload_flow(link.j, link.i, link.t) + flow(ell);
    else
        power_flow(link.i, link.j, link.t) = ...
            power_flow(link.i, link.j, link.t) - flow(ell);
        power_flow(link.j, link.i, link.t) = ...
            power_flow(link.j, link.i, link.t) + flow(ell);
    end
end

% 仅对绘图副本清理求解器产生的近零数值噪声，不修改原始求解结果。
workload_flow(abs(workload_flow) < 1e-4) = 0;
power_flow(abs(power_flow) < 1e-6) = 0;

origin_cells = cell(41, number_period);
audit_rows = cell(26, 6);
audit_index = 0;
origin_row = 1;

for dc = 1:number_dc
    origin_cells{origin_row, 1} = sprintf('DCP%d_workload', dc);
    origin_row = origin_row + 1;
    counterpart = setdiff(1:number_dc, dc);

    for counterparty = counterpart
        origin_cells(origin_row, :) = num2cell(reshape( ...
            workload_flow(dc, counterparty, :), 1, number_period));
        audit_index = audit_index + 1;
        audit_rows(audit_index, :) = { ...
            'Workload', origin_row, dc, counterparty, ...
            'request/s', 'Positive=received; Negative=sent'};
        origin_row = origin_row + 1;
    end

    if dc < number_dc
        origin_row = origin_row + 1;
    end
end

% 保留原 Origin 模板中任务交互块与电力交互块之间的空行。
origin_row = origin_row + 1;

for dc = 1:3
    origin_cells{origin_row, 1} = sprintf('DCP%d_power', dc);
    origin_row = origin_row + 1;
    counterpart = setdiff(1:3, dc);

    for counterparty = counterpart
        origin_cells(origin_row, :) = num2cell(reshape( ...
            power_flow(dc, counterparty, :), 1, number_period));
        audit_index = audit_index + 1;
        audit_rows(audit_index, :) = { ...
            'Power', origin_row, dc, counterparty, ...
            'kW', 'Positive=received; Negative=sent'};
        origin_row = origin_row + 1;
    end

    if dc < 3
        origin_row = origin_row + 1;
    end
end

assert(origin_row == 42, ...
    'Fig. 10 行布局错误：最后一个数据块应结束于第41行。');

audit_rows = audit_rows(1:audit_index, :);
audit_table = cell2table(audit_rows, 'VariableNames', { ...
    'FlowType', 'OriginRow', 'DCP', 'CounterpartyDCP', ...
    'Unit', 'SignConvention'});
end
