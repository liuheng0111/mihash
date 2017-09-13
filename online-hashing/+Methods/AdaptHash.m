classdef AdaptHash
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
% Training routine for AdaptHash method
%
% INPUTS
% 	Xtrain - (float) n x d matrix where n is number of points 
%       	         and d is the dimensionality 
%
% 	Ytrain - (int)   n x l matrix containing labels, for unsupervised datasets
%
% NOTES
%       Adapted from original AdaptHash implementation
% 	W is d x b where d is the dimensionality 
%       b is the bit length
%
% 	Data arrives in pairs. If number_iterations is 1000, then 
% 	2000 points will be processed

    properties
        alphaa
        beta
        step_size
        code_length
    end
=======
>>>>>>> progress 3

properties
    alpha
    beta
    step_size
end

methods
    function [W, R, obj] = init(obj, R, X, Y, opts)
        % alpha is the alpha in Eq. 5 in ICCV'15 paper
        % beta is the lambda in Eq. 7 in ICCV'15 paper
        % step_size is the step size of SGD
        obj.alpha       = opts.alpha;
        obj.beta        = opts.beta;
        obj.step_size   = opts.stepsize;
        disp(obj)

        % LSH init
        [n, d] = size(X);
        W = randn(d, opts.nbits);
        W = W ./ repmat(diag(sqrt(W'*W))',d,1);
    end % init


    function [W, sampleIdx] = train1batch(obj, W, R, X, Y, I, t, opts)
        [n, d] = size(X);
        sampleIdx = I(2*t-1: 2*t);
        Xsample = X(sampleIdx, :);

        ttY = W' * Xsample';
        tY  = 2 * single(ttY > 0) - 1;
        Dh  = sum(tY(:,1) ~= tY(:,2));

        if opts.unsupervised
            s = affinity(Xsample(1, :), Xsample(2, :), [], [], opts);
        else
            s = affinity([], [], Y(sampleIdx(1), :), Y(sampleIdx(2), :), opts);
        end
        s = 2 * s - 1;
        if s > 0
            loss = max(0, Dh - (1 - obj.alpha)*opts.nbits);
            ind  = find(tY(:,1) ~= tY(:,2));
            cind = find(tY(:,1) == tY(:,2));
        else
            loss = max(0, obj.alpha*opts.nbits - Dh);
            ind  = find(tY(:,1) == tY(:,2));
            cind = find(tY(:,1) ~= tY(:,2));
        end

        if loss > 0
            [ck,~] = max(abs(ttY),[],2);
            [~,ci] = sort(ck,'descend');
            ck = find(ismember(ci,ind) == 1);
            ind = ci(ck);
            ri = randperm(length(ind));
            if length(ind) > 0
                cind = [cind;ind(ceil(loss/1)+1:length(ind))];
            end

            v = W' * Xsample(1,:)'; % W' * xi
            u = W' * Xsample(2,:)'; % W' * xj

            w = (2 ./ (1 + exp(-v)) - 1) ; % f(W' * xi)
            z = (2 ./ (1 + exp(-u)) - 1) ; % f(W' * xj)

            M1 = repmat(Xsample(1,:)',1,opts.nbits);
            M2 = repmat(Xsample(2,:)',1,opts.nbits);

            t1 = exp(-v) ./ ((1 + exp(-v)).^2) ; % f'(W' * xi)
            t2 = exp(-u) ./ ((1 + exp(-u)).^2) ; % f'(W' * xj)

            D1 =  diag(2 .* z .* t1);
            D2 =  diag(2 .* w .* t2);

            M = obj.step_size * (2 * (w' * z - opts.nbits * s) * (M1 * D1 + M2 * D2));
            M(:, cind) = 0;
            M = M + obj.beta * W*(W'*W - eye(opts.nbits));
            W = W - M ;
            W = W ./ repmat(diag(sqrt(W'*W))',d,1);
        end 
    end % train1batch


    function H = encode(obj, W, X, isTest)
        H = (X * W) > 0;
    end

    function P = get_params(obj)
        P = [];
    end

end % methods

end % classdef
