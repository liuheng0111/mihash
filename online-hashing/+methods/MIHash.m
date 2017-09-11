classdef MIHash
% Copyright (c) 2017, Fatih Cakir, Kun He, Saral Adel Bargal, Stan Sclaroff 
% All rights reserved.
% 
% If used for academic purposes please cite the below paper:
%
% "MIHash: Online Hashing with Mutual Information", 
% Fatih Cakir*, Kun He*, Sarah Adel Bargal, Stan Sclaroff
% (* equal contribution)
% International Conference on Computer Vision (ICCV) 2017
% 
% Usage of code from authors not listed above might be subject
% to different licensing. Please check with the corresponding authors for
% additioanl information.
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are met:
% 
% 1. Redistributions of source code must retain the above copyright notice, this
%    list of conditions and the following disclaimer.
% 2. Redistributions in binary form must reproduce the above copyright notice,
%    this list of conditions and the following disclaimer in the documentation
%    and/or other materials provided with the distribution.
% 
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
% ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
% WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
% DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
% ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
% (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
% ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
% (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
% SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
% 
% The views and conclusions contained in the software and documentation are those
% of the authors and should not be interpreted as representing official policies,
% either expressed or implied, of the FreeBSD Project.
%
%------------------------------------------------------------------------------
% Training routine for the MIHash method, see demo_mutualinfo.m .
%
% INPUTS
% 	Xtrain - (float) n x d matrix where n is number of points 
%       	         and d is the dimensionality 
%
% 	Ytrain - (int)   n x l matrix containing labels, for unsupervised datasets
% 			 might be empty, e.g., LabelMe.
%     thr_dist - (int)   For unlabelled datasets, corresponds to the distance 
%		         value to be used in determining whether two data instance
% 		         are neighbors. If their distance is smaller, then they are
% 		         considered neighbors.
%	       	         Given the standard setup, this threshold value
%		         is hard-wired to be compute from the 5th percentile 
% 		         distance value obtain through 2,000 training instance.
% 			 see load_gist.m . 
% 	prefix - (string) Prefix of the "checkpoint" files.
%   test_iters - (int)   A vector specifiying the checkpoints, see train.m .
%   trialNo    - (int)   Trial ID
%	opts   - (struct)Parameter structure.
%
% OUTPUTS
%  train_time  - (float) elapsed time in learning the hash mapping
%  update_time - (float) elapsed time in updating the hash table
%  res_time    - (float) elapsed time in maintaing the reservoir set
%  ht_updates  - (int)   total number of hash table updates performed
%  bit_computed_all - (int) total number of bit recomputations, see update_hash_table.m
% 
% NOTES
% 	W is d x b where d is the dimensionality 
%            and b is the bit length / # hash functions
%   Reservoir is initialized with opts.initRS instances

properties
    no_bins
    sigscale
    stepsize
    decay
    initRS
end

methods
    function [W, R, obj] = init(obj, R, X, Y, opts)
        obj.no_bins  = opts.no_bins;
        obj.sigscale = opts.sigscale;
        obj.stepsize = opts.stepsize;
        obj.decay    = opts.decay;
        obj.initRS   = opts.initRS;
        disp(obj)

        % LSH init
        [n, d] = size(X);
        W = randn(d, opts.nbits);
        W = W ./ repmat(diag(sqrt(W'*W))',d,1);

        % start w/ nonempty reservoir to stabilize gradients early on
        if opts.reservoirSize > 0 
            ind = randperm(size(X, 1), obj.initRS);
            Xinit = X(ind, :);
            if isempty(Y), Yinit = [];
            else, Yinit = Y(ind, :); end
            [R, ~] = update_reservoir(R, Xinit, Yinit, opts.reservoirSize, ...
                W, opts.unsupervised);
        end
    end


    function [W, ind] = train1batch(obj, W, R, X, Y, I, t, opts)
        ind = I(t);
        Xi  = X(ind, :);
        if opts.unsupervised
            Yi = [];
        else
            Yi = Y(ind, :);
        end    

        % compute MI gradients wrt. input point
        Aff  = affinity(Xi, R.X, Yi, R.Y, opts);
        grad = obj.mi_gradients(W, R, Xi, Yi, Aff);

        % sgd
        lr = obj.stepsize / (1 + obj.decay*t);
        W  = W - lr * grad;
    end


    function grad = mi_gradients(obj, W, R, X, Y, Aff)
        %
        % INPUTS									   
        %     W   - DxB matrix, contains hash function parameters
        %     R   - reservoir struct
        %     X   - 1xD, data point
        %     Y   - label
        %     Aff - 1xR.size, affinity vector
        %
        % OUTPUTS
        %     grad - gradient matrix, see Eq. 11 in MIHash paper, each column
        %            contains the gradients of a single hash function

        assert(isequal(size(Aff), [size(X, 1), R.size]));

        % RELAXED hash codes to interval [-1, 1]
        phiR = sigmoid(R.X * W, obj.sigscale);  % reservoir_size x nbits
        phiX = sigmoid(  X * W, obj.sigscale);  % 1 x nbits

        % compute distances from hash codes
        nbits = size(W, 2);
        hdist = (2*phiX - 1) * (2*phiR - 1)';     % 1 x reservoir_size
        hdist = (nbits - hdist) / 2;   

        nbins = obj.no_bins;
        Cents = linspace(0, nbits, nbins+1);
        Delta = nbits / nbins;

        % estimate P(D|+), P(D|-), P(D)
        pDCp  = zeros(1, nbins+1);
        pDCn  = zeros(1, nbins+1);
        for i = 1 : nbins+1
            pulse = obj.triPulse(hdist, Cents(i), Delta);
            pDCp(i) = sum(pulse .*  Aff);
            pDCn(i) = sum(pulse .* ~Aff);
        end
        pD = pDCp + pDCn;
        pD = pD ./ sum(pD);
        if sum(pDCp) ~= 0, pDCp = pDCp ./ sum(pDCp); end;
        if sum(pDCn) ~= 0, pDCn = pDCn ./ sum(pDCn); end;
        prCp = sum(Aff) / numel(Aff);
        prCn = 1 - prCp;
        assert(sum(abs((pDCp*prCp+ pDCn*prCn) - pD)) < 1e-6);

        % nbits x reservoir_size matrix: each column is --> 
        % \partial d_h(x, x^r) / \partial \Phi(x) = -\Phi(x^r) / 2
        d_dh_phi = -0.5 * phiR'; 

        d_delta_phi = zeros(nbits, R.size, nbins+1);
        d_pDCp_phi  = zeros(nbins+1, nbits);
        d_pDCn_phi  = zeros(nbins+1, nbits);
        for i = 1:nbins+1
            A = obj.dTriPulse(hdist, Cents(i), Delta);
            % each column of below matrix (RHS) --> 
            % [\partial \delta_{x^r,l} / \partial d_h(x, x^r)] 
            %      x [\partial d_h(x, x^r) / \partial \Phi(x)] 
            % = \partial \delta_{x^r,l} / \partial \Phi(x)
            d_delta_phi(:,:,i) = bsxfun(@times, d_dh_phi, A); 
        end

        for i=1:nbins+1
            % \partial p_{D,l}^+ / \partial \Phi(x)
            % having computed d_delta_phi, we just some the respective columns
            % that correspond to positive neighbors. 
            if any(Aff)
                d_pDCp_phi(i,:) = sum(d_delta_phi(:, Aff, i),2)'./sum(Aff); 
            end
            % similar to above computation but for 
            % \partial p_{D,l}^- / \partial Phi(x)
            if any(~Aff)
                d_pDCn_phi(i,:) = sum(d_delta_phi(:, ~Aff, i),2)'./sum(~Aff); 
            end
        end
        % \partial p_{D,l} / \partial \Phi(x)
        d_pQ_phi = d_pDCp_phi*prCp + d_pDCn_phi*prCn;
        t_log = ones(1, nbins+1);
        idx = (pD > 0);
        t_log(idx) = t_log(idx) + log2(pD(idx));

        % \partial H(D) / \Phi(x)
        d_H_phi = sum(bsxfun(@times, d_pQ_phi, t_log'), 1)'; % column vector

        t_log_p = ones(1, nbins+1);
        t_log_n = ones(1, nbins+1);
        idx1 = (pDCp > 0);
        idx2 = (pDCn > 0);
        t_log_p(idx1) = t_log_p(idx1) + log2(pDCp(idx1));
        t_log_n(idx2) = t_log_n(idx2) + log2(pDCn(idx2));

        % \partial H(D|C) / \partial \Phi(x)
        d_cond_phi = prCp * sum(bsxfun(@times, d_pDCp_phi, t_log_p'),1)' + ...
            prCn * sum(bsxfun(@times, d_pDCn_phi, t_log_n'), 1)';

        % This is equal to the gradient of negative MI
        d_MI_phi = d_H_phi - d_cond_phi; 

        % Since \Phi(x) = [\phi_1(x),...,\phi_b(x)] where 
        % \phi_i(x) = \sigma(w_i^t \times x), take gradient of each \phi_i wrt 
        % w_i, and multiply the resulting vector with corresponding entry in 
        % d_MI_phi
        ty = obj.sigscale * (X * W)'; % a vector
        grad = (bsxfun(@times, bsxfun(@times, repmat(X', 1, length(ty)), ...
            (sigmoid(ty, 1) .* (1 - sigmoid(ty, 1)) .* obj.sigscale)'), d_MI_phi'));
    end


    function y = triPulse(obj, x, mid, delta)
        ind = (x > mid-delta) & (x <= mid+delta);    
        y   = 1 - abs(x - mid) / delta;
        y   = y .* ind;
    end


    function y = dTriPulse(obj, x, mid, delta)
        ind1 = (x > mid-delta) & (x <= mid);
        ind2 = (x > mid) & (x <= mid+delta);
        y = (ind1 - ind2) / delta;
    end

end % methods

end % classdef
