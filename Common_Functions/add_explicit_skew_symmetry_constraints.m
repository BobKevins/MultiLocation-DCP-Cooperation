function [constraints, directional_flow] = ...
        add_explicit_skew_symmetry_constraints(cfg, canonical_flow, link_indices)
%ADD_EXPLICIT_SKEW_SYMMETRY_CONSTRAINTS 显式构造工作负载流的反对称关系。
%
% 每条原有无序 DCP 链路 (i,j), i<j，已有一个有符号规范流 canonical_flow。
% 本函数额外定义两个方向变量 Psi(i,j) 与 Psi(j,i)，并显式施加
% Psi(i,j) + Psi(j,i) = 0。规范流仍供原模型的负载平衡和成本模块使用，
% 因而本函数只用于检验“显式反对称矩阵约束”本身的数值和计算影响。
%
% 输入：
%   cfg            - 统一参数结构。
%   canonical_flow - 原模型的有符号链路流，维度：链路数 x 1。
%   link_indices   - 需要显式展开的工作负载链路编号。
%
% 输出：
%   constraints      - 显式方向变量与反对称关系。
%   directional_flow - [链路数 x 2]，两列依次为 Psi(i,j)、Psi(j,i)。

%% ================================== 00 工作负载链路检查 ==================================
link_indices = link_indices(:);
assert(all(cfg.link_type(link_indices) <= 2), ...
    '显式反对称约束仅适用于交互式和批处理工作负载链路。');

%% ================================== 01 显式双向变量与反对称约束 ==================================
number_selected_link = numel(link_indices);
directional_flow = sdpvar(number_selected_link, 2, 'full');                    % [Psi(i,j), Psi(j,i)]
constraints = [];

for local_link = 1:number_selected_link
    ell = link_indices(local_link);

    % 第一列与原有规范流一致；第二列由显式反对称约束确定为其相反数。
    constraints = [constraints, ...
        directional_flow(local_link, 1) == canonical_flow(ell), ...
        directional_flow(local_link, 1) + directional_flow(local_link, 2) == 0]; %#ok<AGROW>
end
end
