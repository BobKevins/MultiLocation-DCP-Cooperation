function export_info = export_paper_figure_data( ...
        cfg, centralized_result, admm_result, stage1_verification, ...
        stage2_verification, shapley_result, paper_scenarios)
%EXPORT_PAPER_FIGURE_DATA 将论文 Fig. 5--13 和正文结果表整理为 Excel 数据。
%
% 本函数仅进行结果读取、矩阵重排和 Excel 导出，不建立优化变量、不添加约束、
% 不调用求解器。Fig. 10--13 和集中式--ADMM 对比表使用当前主算例结果；
% 全部图表来自当前运行；不读取已有论文图表工作簿。

%% ================================== 00 文件路径 ==================================
figure_workbook = fullfile(cfg.root_directory, 'Results', ...
    'paper_case_figure_data.xlsx');
if ~isfolder(fileparts(figure_workbook))
    mkdir(fileparts(figure_workbook));
end

%% ================================== 01 Fig. 5--6 正式绘图数据 ==================================
m1 = paper_scenarios.methods{1};
m2 = paper_scenarios.methods{2};
figure05_cells = {'Method', 'TotalCost_USD', 'PurchaseCost_USD', ...
    'SellRevenue_USD', 'CarbonCost_USD', 'UserPayment_USD'; ...
    'Without user interaction', m1{1}.end_to_end_cost, m1{1}.cost_purchase, ...
        m1{1}.revenue_sell, m1{1}.cost_carbon, m1{1}.payment; ...
    'With user interaction', m2{1}.end_to_end_cost, m2{1}.cost_purchase, ...
        m2{1}.revenue_sell, m2{1}.cost_carbon, m2{1}.payment};
% 模板中的 origin 表示用户提交的原始任务曲线，不是 M1 求解后的批处理曲线。
origin_workload = cfg.workload_inter_origin(1, :) + cfg.workload_batch_origin(1, :);
adjusted_workload = sum(m2{1}.workload_inter_group + m2{1}.adjusted_batch, 1);
inter_weight = m2{1}.workload_inter_group;
batch_weight = m2{1}.workload_batch_group;
inter_delay = sum(m2{1}.selected_inter_delay .* inter_weight, 1) ./ ...
    max(sum(inter_weight, 1), eps);
batch_delay = sum(m2{1}.selected_batch_delay .* batch_weight, 1) ./ ...
    max(sum(batch_weight, 1), eps);
figure06_cells = [{'TimePeriod', 'Workload_origin_request_per_s', ...
    'Workload_adjusted_request_per_s', 'InteractiveDelay_s', 'BatchDelay_h', ...
    'ElectricityPrice_USD_per_MWh'}; num2cell([(1:cfg.number_period)', ...
    origin_workload', adjusted_workload', inter_delay', batch_delay', ...
    cfg.price_ele(1, :)'])];

%% ================================== 02 Fig. 7 三维成本数据 ==================================
[inter_grid, batch_grid] = ndgrid(paper_scenarios.inter_set, ...
    paper_scenarios.batch_set);
figure07_cells = [{'InteractiveDelay_s', 'BatchDelay_h', 'OperationCost_USD'}; ...
    num2cell([inter_grid(:), batch_grid(:), paper_scenarios.cost_grid(:)])];

%% ================================== 03 Fig. 8 延时调节效果 ==================================
% 两幅子图必须由同一个固定延时物理成本网格计算，另一类延时保持该行给定值。
[figure08_book1_cells, figure08_book2_cells] = ...
    build_delay_reduction_blocks(cfg, paper_scenarios);

%% ================================== 04 Fig. 9 敏感性数据 ==================================
c = paper_scenarios.user_sensitivity.coefficient_plot;
d = paper_scenarios.user_sensitivity.delay_plot;
figure09_inter_cells = [{'CoefficientFactor', 'DCP_OperationCost_USD', ...
    'UserPayment_USD'}; num2cell([c.InterCoefficientFactor, ...
    c.Inter_DCP_OperationCost_USD, c.Inter_UserPayment_USD])];
figure09_batch_cells = [{'CoefficientFactor', 'DCP_OperationCost_USD', ...
    'UserPayment_USD'}; num2cell([c.BatchCoefficientFactor, ...
    c.Batch_DCP_OperationCost_USD, c.Batch_UserPayment_USD])];
figure09_delay_cells = [d.Properties.VariableNames; table2cell(d)];
baseline = abs(c.InterCoefficientFactor-1) < 1e-12;
assert(nnz(baseline) == 1, 'Fig. 9 缺少唯一 1.0 倍系数基准。');
assert(abs(c.Inter_DCP_OperationCost_USD(baseline)-m2{1}.end_to_end_cost) < 1e-3, ...
    'Fig. 5 M2 与 Fig. 9 当前基准成本不一致，请核查单园区场景。');
base_inter = find(abs(paper_scenarios.inter_set-cfg.time_tolerance_inter_original) < 1e-12);
base_batch = find(abs(paper_scenarios.batch_set-cfg.time_tolerance_batch_original) < 1e-12);
assert(abs(paper_scenarios.cost_grid(base_inter, base_batch)-m1{1}.end_to_end_cost) < 1e-6, ...
    'Fig. 5 M1 与 Fig. 7 原始延时物理成本不一致。');

%% ================================== 05 Fig. 10 DCP 交互数据 ==================================
[figure10_cells, ~] = build_figure10_blocks( ...
    cfg, admm_result.consensus_flow);

%% ================================== 06 Fig. 11 收敛质量数据 ==================================
assert(isfield(stage1_verification, 'figure11_origin'), ...
    '必须传入本次 Stage 1 运行的 Fig. 11 收敛数据。');
figure11_origin_table = stage1_verification.figure11_origin;

%% ================================== 07 Fig. 12--13 成本与利益分配 ==================================
[figure12_cells, figure13_cells] = build_shapley_figure_blocks( ...
    paper_scenarios, shapley_result);

%% ================================== 08 正文结果表 ==================================
table01_cells = build_method_cost_block(paper_scenarios);
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
total_row = find(strcmp(table01_cells(:, 1), 'Total Cost (USD)'));
table01_components = cell2mat(table01_cells(2:total_row-1, 2:5));
table01_total = cell2mat(table01_cells(total_row, 2:5));
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
        paper_scenarios, shapley_result)
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

% M1 独立求解；M2 与 M5 来自本次联盟成本及 Shapley 分配。
m1_cost = cellfun(@(item) item.end_to_end_cost, paper_scenarios.methods{1})';
figure13_cells = cell(4, 7);
figure13_cells(1, :) = {'Method', 'DCP1', 'DCP2', 'DCP3', 'DCP4', 'DCP5', 'Overall'};
figure13_cells(2, :) = [{'M1'}, num2cell(m1_cost), {sum(m1_cost)}];
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

function [book1, book2] = build_delay_reduction_blocks(cfg, scenarios)
%BUILD_DELAY_REDUCTION_BLOCKS 固定另一类延时，按原始档位计算降低金额及比例。

inter = scenarios.inter_set;
batch = scenarios.batch_set;
cost = scenarios.cost_grid;
base_inter = find(abs(inter - cfg.time_tolerance_inter_original) < 1e-12);
base_batch = find(abs(batch - cfg.time_tolerance_batch_original) < 1e-12);
assert(isscalar(base_inter) && isscalar(base_batch), '缺少原始延时基准档位。');
other_inter = setdiff(1:numel(inter), base_inter, 'stable');
other_batch = setdiff(1:numel(batch), base_batch, 'stable');
book1 = cell(numel(inter)+1, 1+2*numel(other_batch));
book1(1, 1) = {'FixedInteractiveDelay_s'};
book1(2:end, 1) = num2cell(inter(:));
for index = 1:numel(other_batch)
    target = other_batch(index);
    reduction = cost(:, base_batch) - cost(:, target);
    book1(1, 2*index:2*index+1) = { ...
        sprintf('Batch%gh_AbsReduction_USD', batch(target)), ...
        sprintf('Batch%gh_ReductionFraction', batch(target))};
    book1(2:end, 2*index:2*index+1) = ...
        num2cell([reduction, reduction ./ cost(:, base_batch)]);
end
book2 = cell(numel(batch)+1, 2+2*numel(other_inter));
book2(1, 1:2) = {'FixedBatchDelay_h', 'BaseCost_USD'};
book2(2:end, 1:2) = num2cell([batch(:), cost(base_inter, :)']);
for index = 1:numel(other_inter)
    target = other_inter(index);
    reduction = cost(base_inter, :)' - cost(target, :)';
    book2(1, 2*index+1:2*index+2) = { ...
        sprintf('Inter%gs_AbsReduction_USD', inter(target)), ...
        sprintf('Inter%gs_ReductionFraction', inter(target))};
    book2(2:end, 2*index+1:2*index+2) = ...
        num2cell([reduction, reduction ./ cost(base_inter, :)']);
end
end

function cells = build_method_cost_block(scenarios)
%BUILD_METHOD_COST_BLOCK M2--M5 成本分项来自本次实际逐 DCP 求解结果。

components = zeros(5, 4);
totals = zeros(1, 4);
for index = 1:4
    results = scenarios.methods{index+1};
    components(:, index) = [ ...
        sum(cellfun(@(r) r.cost_purchase-r.revenue_sell, results)); ...
        sum(cellfun(@(r) r.cost_carbon, results)); ...
        sum(cellfun(@(r) r.transfer_cost, results)); ...
        sum(cellfun(@(r) r.payment, results)); ...
        sum(cellfun(@(r) r.cost_storage, results))];
    totals(index) = sum(cellfun(@(r) r.end_to_end_cost, results));
end
assert(max(abs(sum(components, 1)-totals)) < 1e-6, '当前方法成本分项未闭合。');
names = {'Electricity Cost (USD)'; 'Carbon Cost (USD)'; ...
    'Transmission Cost (USD)'; 'Compensation Cost (USD)'; 'Storage Cost (USD)'};
if all(abs(components(5, :)) < 1e-8)
    components = components(1:4, :);
    names = names(1:4);
end
reduction = totals(1)-totals;
percentage = 100*reduction/totals(1);
cells = [{'Cost component', 'M2', 'M3', 'M4', 'M5'}; ...
    [names, num2cell(components)]; ...
    [{'Total Cost (USD)'}, num2cell(totals)]; ...
    [{'Cost Reduction (USD)'}, num2cell(reduction)]; ...
    [{'Cost Reduction (%)'}, num2cell(percentage)]];
cells(end-1:end, 2) = {'--'; '--'};
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
