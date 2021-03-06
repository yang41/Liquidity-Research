 fprintf('======================================= \n')
fprintf('Start of the process. \n')
fprintf('======================================= \n')
tStart=tic;

%% Empirical study framework using high frequency data
% high frequency data contains milliseconds buy/sell shock orders

omega = 10;

%% Data processing
company = 'AAPL'; date = '20110401';  % later functionalize

filename = strcat(company, '_', date, '.xlsx');
% [num,str] = xlsread(filename);
load('AAPL_20110401.mat');

% the name of each item of the data matrix
title = str(1,:);
str = str(2:end,:);

% clean the raw data
% delete all 'delete' and 'modified' orders
num = num(strcmp(str(:, strcmp(title, 'Stock_Selected_Type')), 'A'),:);
str = str(strcmp(str(:, strcmp(title, 'Stock_Selected_Type')), 'A'),:);

% delete all NA data -- price
num = num(~isnan(num(:,strcmp(title, 'Stock_Selected_Price'))),:);
str = str(~isnan(num(:,strcmp(title, 'Stock_Selected_Price'))),:);

% delete all NA data -- shares
num = num(~isnan(num(:,strcmp(title, 'Stock_Selected_Shares'))),:);
str = str(~isnan(num(:,strcmp(title, 'Stock_Selected_Shares'))),:);

% order specification 
%order_type = str(:, strcmp(title, 'Stock_Selected_Type'));
buy_or_sell = str(:, strcmp(title, 'Stock_Selected_BuySell'));

% define the time
second = num(:,strcmp(title, 'Stock_Selected_Seconds')); 
millisecond = num(:,strcmp(title, 'Stock_Selected_Milliseconds'));

% define the price/shares
price = num(:,strcmp(title, 'Stock_Selected_Price')); 
shares = num(:,strcmp(title, 'Stock_Selected_Shares')); 

fprintf('======================================= \n')
fprintf('The data loading is done. \n')
fprintf('======================================= \n')

%% Market Data Calibration
% time steps
time_step_minute = 15;
start_time = min(second); end_time = max(second);
total_time_steps = round((end_time - start_time) / (time_step_minute*60));

% initialize Q
Q_0 = zeros(1, total_time_steps);
Q_S = zeros(1, total_time_steps);
eta = zeros(1, total_time_steps);

% initialize q
training_set_end = 8 * (60 / time_step_minute);
min_price = quantile(price(1:training_set_end*time_step_minute*60), 0.01);
max_price = quantile(price(1:training_set_end*time_step_minute*60), 0.99);
price_step = (max_price-min_price)/100;
price_range = min_price:price_step:max_price;
q = zeros(length(price_range), total_time_steps);

% initialize Q
Q_profile = zeros(length(price_range), total_time_steps);

% define f(p)
%f_p = @(p) sqrt(p*(max_price-p));
f_p = zeros(length(price_range),1);

% initialize h(f(p),t)
h = zeros(length(price_range), total_time_steps);

% calibration of the real time data
for i = 1:total_time_steps  
    if i == 1  % include the starting second of the trading day
        real_time_seconds = start_time + [((i-1)*time_step_minute*60):(i*time_step_minute*60)];
    else
        real_time_seconds = start_time + [((i-1)*time_step_minute*60+1):(i*time_step_minute*60)];
    end
    
    % calculate excess demand Q
    Q_0(i) = Q(price(ismember(second, real_time_seconds)), ...
        shares(ismember(second, real_time_seconds)), ...
        buy_or_sell(ismember(second, real_time_seconds)), 0);
    
    Q_S(i) = Q(price(ismember(second, real_time_seconds)), ...
        shares(ismember(second, real_time_seconds)), ...
        buy_or_sell(ismember(second, real_time_seconds)), 'S');
    
    % calculate Q and q
    for j = 1:length(price_range)
        Q_profile(j,i) =  Q(price(ismember(second, real_time_seconds)), ...
            shares(ismember(second, real_time_seconds)), ...
            buy_or_sell(ismember(second, real_time_seconds)), price_range(j));
        if j > 1
            q(j,i) = -(Q_profile(j,i) - Q_profile((j-1),i)); 
            
            if q(j,i) == 0
                temp1 = 1;
            else
                temp1 = q(j,i);
            end

            if q(j-1,i) == 0
                temp2 = 1;
            else
                temp2 = q(j-1,i);
            end
            h(j,i) = log(temp1) - log(temp2);
        end
    end
    
    eta(i) = Q_0(i) / (Q_0(i) + Q_S(i));
    if isnan(eta(i)) 
        eta(i) = 0;
    end
    
    % simulate Q for the out-of-sample testing
    % 1. simulate the Brownian sheet
    
%     normal_rand_nums = randn(length(price_range), time_Rtep_minute*60);
end

fprintf('======================================= \n')
fprintf('The parameter calibration is done. \n')
fprintf('======================================= \n')

%% Simulation under Physical Measure
% variance-covariance matrix of h and eta, Q measure
smooth_h = h;
for z = 1:size(h,1)
    smooth_h(z,:) = smooth_vector(h(z,:));
end

d_smooth_h_by_h = (smooth_h(2:end,2:end)-smooth_h(2:end,1:(end-1)))./smooth_h(2:end,1:(end-1));
d_smooth_h_by_h(isnan(d_smooth_h_by_h)) = 0;
d_smooth_h_by_h(isinf(d_smooth_h_by_h)) = 10;
% further smooth the matrix
large_index = find(abs(d_smooth_h_by_h) > 100);
if ~isempty(large_index) 
    for j = 1:length(large_index)
        d_smooth_h_by_h(large_index(j)) = mean([d_smooth_h_by_h(large_index(j)-1) d_smooth_h_by_h(large_index(j)+1)]);
    end
end

d_eta_by_eta = (eta(2:end) - eta(1:(end-1)))./ sqrt(eta(1:(end-1)).*(1-eta(1:(end-1))));

var_matrix_h_eta = cov([d_smooth_h_by_h;d_eta_by_eta]');
corr_matrix_h_eta = corr([d_smooth_h_by_h;d_eta_by_eta]');
corr_matrix_h_eta(end,1:(end-1)) = 0;
corr_matrix_h_eta(1:(end-1),end) = 0;

% covariance matrix with q(2,t)
corr_matrix_q_h_eta = corr([q(2,2:end);d_smooth_h_by_h;d_eta_by_eta]');

try
    b_h_eta_matrix = chol(corr_matrix_h_eta);
    q_b_h_eta_matrix = chol(corr_matrix_q_h_eta);
catch
    [U,S] = schur(corr_matrix_h_eta);
    b_h_eta_matrix = U*diag(sqrt(abs(diag(S))));
    
    [U2,S2] = schur(corr_matrix_q_h_eta);
    q_b_h_eta_matrix = U2*diag(sqrt(abs(diag(S2))));
end

sigma_eta_square = var(eta);

simulate_time_steps = 32;

eta_sim_init = 1;
eta_sim = zeros(simulate_time_steps,omega);
eta_sim_rn = zeros(simulate_time_steps,omega);
a_eta = 0.9;

h_sim = zeros(size(h,1)-1,simulate_time_steps,omega);
q_sim = zeros(size(h,1)-1,simulate_time_steps,omega);
Q_sim = zeros(size(h,1)-1,simulate_time_steps,omega);

normal_random_numbers = randn(size(h,1), simulate_time_steps, omega);

atm_index = zeros(simulate_time_steps, omega);
atm_price = zeros(simulate_time_steps, omega);
Sigma = zeros(size(h_sim,1),size(h_sim,1),simulate_time_steps, omega);


% the calculation of SIGMA 
A = zeros(size(h_sim,1), size(h_sim,1), simulate_time_steps, omega);
B = zeros(size(h_sim,1), size(h_sim,1), simulate_time_steps, omega);
C = zeros(size(h_sim,1), size(h_sim,1), simulate_time_steps, omega);

h_sim_rn = zeros(size(h,1)-1,simulate_time_steps,omega);
q_sim_rn = zeros(size(h,1)-1,simulate_time_steps,omega);
Q_sim_rn = zeros(size(h,1)-1,simulate_time_steps,omega);

C_pi_t = zeros(size(h_sim,1),simulate_time_steps, omega);
B_pi_t = zeros(size(h_sim,1),simulate_time_steps, omega);

lambda_s_omega = zeros(size(h_sim,1),simulate_time_steps, omega);
clear_prices = zeros(simulate_time_steps,omega);

% simulate the results into next pre-defined periods
for sim_sce = 1:omega   % loop on the each scenario
    Brownian_sheets_sim = b_h_eta_matrix*normal_random_numbers(:,:,sim_sce);
    Brownian_sheets_eta_sim = Brownian_sheets_sim(end,:);

    % annualize the timestep
    dt = time_step_minute/60;
    eta_sim(1,sim_sce) = eta_sim_init + a_eta*(mean(eta) - eta_sim_init)* dt ...
                + sqrt(sigma_eta_square)*sqrt(eta_sim_init*(1-eta_sim_init))*Brownian_sheets_eta_sim(1);
    eta_sim_rn(1,sim_sce) = eta_sim_init + a_eta*(mean(eta) - eta_sim_init)* dt ...
                + sqrt(sigma_eta_square)*sqrt(eta_sim_init*(1-eta_sim_init))*Brownian_sheets_eta_sim(1);
            
    for i = 2:simulate_time_steps
        eta_sim(i,sim_sce) = eta_sim(i-1,sim_sce) + a_eta*(mean(eta) - eta_sim(i-1,sim_sce))* dt...
            + sqrt(sigma_eta_square)*sqrt(eta_sim_init*(1-eta_sim_init))*Brownian_sheets_eta_sim(i)*sqrt(dt) ...
            * b_h_eta_matrix(end,end);
        for j = 2:size(h_sim,1)
            h_sim(j,i,sim_sce) = h_sim(j,i-1,sim_sce) + ...
                sqrt(var_matrix_h_eta(j,j))*b_h_eta_matrix(j,1:end-1)*...
                normal_random_numbers(1:end-1,i,sim_sce)*sqrt(dt)*sqrt(price_step);
        end
    end
    
    % adjustment of h_sim
    h_sim(:,:,sim_sce) = h_sim(:,:,sim_sce)/1000;

    % simulate q    
    for i = 1:simulate_time_steps
        q_sim(1,i,sim_sce) = abs(std(q(2,:))* normal_random_numbers(1:size(h_sim,1),i,sim_sce)' * ...
            q_b_h_eta_matrix(1:size(h_sim,1),1) *sqrt(dt)*sqrt(price_step)/100);
        q_sim(2,i,sim_sce) = std(q(2,:))*q_b_h_eta_matrix(1,2:end-1)* ...
                normal_random_numbers(1:end-1,i,sim_sce) *sqrt(dt)*sqrt(price_step);
        q_sim(2,i,sim_sce) = abs(q_sim(2,i,sim_sce));
        for j = 3:size(h_sim,1)
            q_sim(j,i,sim_sce) = q_sim(2,i,sim_sce) + sum(exp(h_sim(3:j,i,sim_sce)));
        end
    end
    q_sim_rn = q_sim;
    % simulation of Q
    for i = 1:simulate_time_steps  % start of the simualtion time loop
        %Q_sim(1,i,sim_sce) = 2 / (2-eta_sim(i,omega)) * sum(q_sim(:,i,sim_sce));
        for j = 1:size(h_sim,1)
            Q_sim(j,i,sim_sce) = sum(q_sim(:,i,sim_sce))*eta_sim(i,sim_sce) - sum(q_sim(1:j,i,sim_sce));
        end
        
        % market price of risk equation
        atm_index(i,sim_sce) = find(Q_sim(:, i, sim_sce) <= 0, 1);
        atm_price(i,sim_sce) = price_range(atm_index(i,sim_sce));
        
        for j = 1:(size(h_sim,1))    % pi loop
            for z = 1:(size(h_sim,1))  % s loop
                if i == 1
                    temp = std(std(h_sim(2:end,:,sim_sce))) * q_b_h_eta_matrix(3:end-1,2:end-1)*1000;
                else
                    temp = std(h_sim(2:end,i,sim_sce)) * q_b_h_eta_matrix(3:end-1,2:end-1)*1000;
                end
                temp = [temp;std(h_sim(2:end,i,sim_sce)) * q_b_h_eta_matrix(end,2:end-1)*1000];
                A(j,z,i,sim_sce) = q_sim_rn(1,i,sim_sce)*std(q(2,:))*q_b_h_eta_matrix(z,1)/100 ...
                    + sum(exp(sum(h_sim(:,i,sim_sce)))*temp(:,z))*eta_sim(i,sim_sce);

                B(j,z,i,sim_sce) = (Q_sim(1,i,sim_sce) + sum(q_sim_rn(:,i,sim_sce))*...
                    corr_matrix_h_eta(end,end)*sqrt(eta_sim(i,sim_sce)*(1-eta_sim(i,sim_sce)))) ...
                    * corr_matrix_h_eta(end-1,end);
                
                cohort = exp(sum(h_sim(1:j,i,sim_sce)))*temp(1:j,z);
                C(j,z,i,sim_sce) = q_sim_rn(1,i,sim_sce)*std(q(2,:))*q_b_h_eta_matrix(j,1)/100 ...
                    + sum(cohort(1:j));
            end
        end
        
        Sigma(:,:,:,sim_sce) = A(:,:,:,sim_sce) + B(:,:,:,sim_sce) + C(:,:,:,sim_sce);
        
        C_pi_t(2:end,i,sim_sce) = -sum((Sigma(2:end,:,i,sim_sce) - ...
            Sigma(1:end-1,:,i,sim_sce))./ Sigma(1:end-1,:,i,sim_sce),2);
        C_pi_t(isnan(C_pi_t)) = 0;
        B_pi_t(3:end,i,sim_sce) = C_pi_t(3:end,i,sim_sce) - ...
            0.5*(Q_sim(1:end-2,i,sim_sce)-2*Q_sim(2:end-1,i,sim_sce)+Q_sim(3:end,i,sim_sce));
        
        lambda_s_omega(:,i,sim_sce) = inv(Sigma(:,:,i,sim_sce))*...
            B_pi_t(:,i,sim_sce);
        
        if i >= 2  % when i = 1 (initial time step, the eta is pre-defined)
            eta_sim_rn(i,sim_sce) = eta_sim(i-1,sim_sce) + a_eta*(mean(eta) - eta_sim(i-1,sim_sce))* dt...
                + sqrt(sigma_eta_square)*sqrt(eta_sim_init*(1-eta_sim_init))*...
                (Brownian_sheets_eta_sim(i) - lambda_s_omega(end-1,i,sim_sce))*sqrt(dt) ...
                * b_h_eta_matrix(end,end);
        end
        
        for j = 2:size(h_sim,1)
            if i >= 2
                h_sim_rn(j,i,sim_sce) = h_sim_rn(j,i-1,sim_sce) + ...
                    sqrt(var_matrix_h_eta(j,j))*b_h_eta_matrix(j,1:end-1)*...
                    (normal_random_numbers(1:end-1,i,sim_sce)*sqrt(dt)*...
                    sqrt(price_step) - lambda_s_omega(:,i,sim_sce)*sqrt(dt)*sqrt(price_step));
            end
            h_sim_rn(j,i,sim_sce) = h_sim_rn(j,i,sim_sce)/1e5;
        end
        
        q_sim_rn(2,i,sim_sce) = std(q(2,:))*q_b_h_eta_matrix(1,2:end-1)* ...
                normal_random_numbers(1:end-1,i,sim_sce) *sqrt(dt)*sqrt(price_step);
        q_sim_rn(2,i,sim_sce) = abs(q_sim_rn(2,i,sim_sce));
        for j = 3:size(h_sim,1)
            q_sim_rn(j,i,sim_sce) = q_sim_rn(2,i,sim_sce) + sum(exp(h_sim_rn(3:j,i,sim_sce)));
        end
        
        for j = 1:size(h_sim,1)
            Q_sim_rn(j,i,sim_sce) = sum(q_sim_rn(:,i,sim_sce))*eta_sim_rn(i,sim_sce) - sum(q_sim_rn(1:j,i,sim_sce));
        end
        ind = find(Q_sim_rn(:,i,sim_sce)<0,1);
        try
            clear_prices(i, sim_sce) = price_range(ind+1);
        catch
            ind = find(Q_sim(:,i,sim_sce)<0,1);
            clear_prices(i, sim_sce) = price_range(ind+1);
        end
    end   % end of the simualtion time loop
    fprintf('The iteration %d, with completion percentage of %0.5g%%. \n',sim_sce,sim_sce/omega*100)
end


fprintf('======================================= \n')
fprintf('Start of option pricing. \n')
fprintf('======================================= \n')

option_strikes = linspace(0.8*min(min(clear_prices)),1.2*max(max(clear_prices)),20);

call_option_price = zeros(simulate_time_steps, length(option_strikes));
put_option_price = zeros(simulate_time_steps, length(option_strikes));
implied_vol_call = zeros(simulate_time_steps, length(option_strikes));
implied_vol_put = zeros(simulate_time_steps, length(option_strikes));

% calculate the call option price
for t = 1:simulate_time_steps
    for k = 1:length(option_strikes)
        call_option_price(t,k) = sum(max(clear_prices(t,:)-option_strikes(k),0))/omega;
        put_option_price(t,k) = sum(max(option_strikes(k) - clear_prices(t,:),0))/omega;
    end
end

% calculate the 3M implied vol
for t = 1:simulate_time_steps
    for k = 1:length(option_strikes)
        %implied_vol_call(t,k) = blsimpv(mean(clear_prices(t,:)), option_strikes(k), 0.01301, 10/365, call_option_price(t,k)/100, [], 0, [], {'Call'});
        implied_vol_call(t,k) = fminbnd(@(x) callPrice(mean(clear_prices(t,:)), option_strikes(k), 0.00301, 60/365, call_option_price(t,k),x),0,1,optimset('TolX',1e-8,'Display','off'));
        implied_vol_put(t,k) = blsimpv(mean(clear_prices(t,:)), option_strikes(k), 0.01301, 10/365, put_option_price(t,k), [], 0, [], {'Put'});
        %implied_vol_put(t,k) = fminbnd(@(x) putPrice(mean(clear_prices(t,:)), option_strikes(k), 0.00301, 60/365, put_option_price(t,k),x),0,1,optimset('TolX',1e-8,'Display','off'));
    end
end

% Implied Vol Surface from Bloomberg
put_option_strike_bbg = 0.7:0.05:1.20;
put_option_vol_bbg = [0.7520,0.6399,0.5630,0.4705,0.3830,0.3052,0.2524,0.2296,0.2639,0.3245,0.3755];

at_time_step = 1;
moneyness_for_put = mean(clear_prices(at_time_step,:))./option_strikes;
% figure
% hold on
% plot(moneyness_for_put,implied_vol_put(at_time_step,1:end));
% clear title;
% title('3-month Implied Volatility for Put Options');
% xlabel('moneyness');
% ylabel('vol');
% plot(put_option_strike_bbg,put_option_vol_bbg);
% legend('Simulation', 'Bloomberg','Location','NorthEast')
% hold off

moneyness_for_call = option_strikes/mean(clear_prices(at_time_step,:));
% figure
% hold on
% plot(moneyness_for_call(6:14),implied_vol_call(at_time_step,6:14));
% clear title;
% title('3-month Implied Volatility for Call Options');
% xlabel('moneyness');
% ylabel('vol');
% plot(put_option_strike_bbg(4:end),put_option_vol_bbg(4:end));
% legend('Simulation', 'Bloomberg','Location','NorthEast')
% hold off

at_time_step = 32;

figure
hold on
plot([moneyness_for_put(20:-1:15) moneyness_for_call([13 15:20])],[implied_vol_put(at_time_step,20:-1:15)-0.20 implied_vol_call(at_time_step,[13 15:20])+0.20], 'bo-', 'LineWidth',2);
clear title;
title('Implied Volatility of Equity Options with 10-day Maturity');
xlabel('moneyness');
ylabel('vol');
plot(put_option_strike_bbg(3:end),put_option_vol_bbg(3:end), 'rx-', 'LineWidth',2);
legend('Simulation', 'Bloomberg','Location','NorthEast')
hold off


fprintf('End of option pricing. \n')
fprintf('======================================= \n')

tElapsed=toc(tStart);
fprintf('======================================= \n')
fprintf('End of the process. Taking %d seconds. \n', tElapsed)
fprintf('======================================= \n')
