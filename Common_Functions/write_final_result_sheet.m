function workbook_file = write_final_result_sheet(project_root, workbook_kind, sheet_name, data)
%WRITE_FINAL_RESULT_SHEET 将当前数值写入最终工作簿，不读取论文结果快照。
% 各入口只更新本次完成的 Sheet，未运行项目不使用旧数据补齐。

assert(ismember(string(workbook_kind), ["paper", "reviewer"]), ...
    '工作簿类型必须为 paper 或 reviewer。');
result_directory = fullfile(project_root, 'Results');
if ~isfolder(result_directory)
    mkdir(result_directory);
end
if strcmp(workbook_kind, 'paper')
    workbook_name = 'paper_case_figure_data.xlsx';
else
    workbook_name = 'reviewer_response_figure_data.xlsx';
end
workbook_file = fullfile(result_directory, workbook_name);
if istable(data)
    cells = [data.Properties.VariableNames; table2cell(data)];
else
    cells = data;
end
assert(iscell(cells) && ~isempty(cells), '最终 Sheet 数据不能为空。');
writecell(cells, workbook_file, 'Sheet', sheet_name, 'WriteMode', 'overwritesheet');
end
