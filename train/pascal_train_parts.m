function model = pascal_train_mixture(cls, n, note)
% Train a model.
%   model = pascal_train(cls, note)
%
% Trains a Dalal & Triggs model.
%
% Arguments
%   cls           Object class to train and evaluate
%                 (The final model has 2*n components)
%   note          Save a note in the model.note field that describes this model

% At every "checkpoint" in the training process we reset the 
% RNG's seed to a fixed value so that experimental results are 
% reproducible.
seed_rand();

% Default to no note
if nargin < 2
  note = '';
end

conf = voc_config();
cachedir = conf.paths.model_dir;

% Load the training data
[pos, neg, impos] = pascal_data(cls, conf.pascal.year);

% Split foreground examples into n groups by aspect ratio
spos = split(pos, n);

max_num_examples = conf.training.cache_example_limit;
num_fp           = conf.training.wlssvm_M;
fg_overlap       = conf.training.fg_overlap;

% Select a small, random subset of negative images
% All data mining iterations use this subset, except in a final
% round of data mining where the model is exposed to all negative
% images
num_neg   = length(neg);
neg_large = neg; % use all of the negative images
neg_perm  = neg(randperm(num_neg));
neg_small = neg_perm(1:min(num_neg, conf.training.num_negatives_small));

impos_with_difficult = pascal_data_diff(cls, conf.pascal.year);
neg_all = merge_pos_neg(impos_with_difficult, neg);

for i = 1:n
  models{i} = root_model(cls, spos{i}, note);
end
model = model_merge(models);

save_file = [cachedir cls '_hard_neg'];
try
  ld = load(save_file);
  model = ld.model; clear ld;
  fprintf('Loaded %s\n', save_file);
catch
  model = model_cnn_init(model);
  model = train(model, impos, neg_small, true, false, 1, 10, ...
                max_num_examples, fg_overlap, num_fp, false, 'hard_neg1');
  model = train(model, impos, neg_small, false, false, 2, 10, ...
                max_num_examples, fg_overlap, num_fp, true, 'hard_neg2');
  save(save_file, 'model');
end

save_file = [cachedir cls '_final'];
try
  ld = load(save_file);
  model = ld.model; clear ld;
  fprintf('Loaded %s\n', save_file);
catch
  model = model_cnn_init(model);

  seed_rand();
  % Add parts to each mixture component
  for i = 1:n
    % Top-level rule for this component
    ruleind = i;
    % Filter to interoplate parts from
    filterind = i;
    model = model_add_parts_no_mirror_sharing(model, model.start, ruleind, ...
                                              filterind, 8, [3 3], 0);
%    % Enable learning location/scale prior
%    bl = model.rules{model.start}(i).loc.blocklabel;
%    model.blocks(bl).w(:)     = 0;
%    model.blocks(bl).learn    = 1;
%    model.blocks(bl).reg_mult = 1;
  end

  model = train(model, impos, neg_small, false, false, 3, 20, ...
                max_num_examples, fg_overlap, num_fp, false, 'hard_parts1');
  model = train(model, impos, neg_all, false, false, 1, 10, ...
                max_num_examples, fg_overlap, num_fp, true, 'hard_parts2');

  save(save_file, 'model');
end
