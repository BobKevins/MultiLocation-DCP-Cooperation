%% ================================== 00 环境初始化 ==================================
clear;
clc;
close all;
case_directory = fileparts(mfilename('fullpath'));
project_root = fileparts(case_directory);
original_path = path;
addpath(fullfile(project_root, 'Common_Functions'));
cleanup_path = onCleanup(@() path(original_path));

%% ================================== 01 当前 Fig. 9 场景求解 ==================================
output_directory = fullfile(case_directory, 'outputs');
sensitivity_result = solve_paper_user_sensitivity(project_root, output_directory);

%% ================================== 02 最终图表更新 ==================================
export_user_sensitivity_sheets(project_root, sensitivity_result);
