# frozen_string_literal: true

RSpec.describe OmniService::Assert do
  subject(:assert_component) { described_class.new(predicate, code:, **options) }

  let(:predicate) { %i[post published?] }
  let(:code) { :not_published }
  let(:options) { {} }

  describe '#call' do
    subject(:result) { assert_component.call(params, **context) }

    let(:params) { { title: 'Hello' } }
    let(:context) { { post: } }
    let(:post) { post_class.new(published: published) }
    let(:published) { true }
    let(:post_class) do
      Struct.new(:published, keyword_init: true) do
        def published?
          published
        end
      end
    end

    context 'when predicate resolves truthy' do
      it 'returns success preserving input' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { post: },
          errors: []
        )
      end
    end

    context 'when predicate resolves falsey' do
      let(:published) { false }

      it 'returns failure with configured code' do
        expect(result).to be_failure & have_attributes(
          params: [params],
          context: { post: },
          errors: [have_attributes(code: :not_published, path: %i[post published?])]
        )
      end
    end

    context 'with nested hash and array path' do
      let(:predicate) { [:post, :comments, 0, :valid?] }
      let(:context) { { post: { comments: [comment] } } }
      let(:comment) { comment_class.new(valid: true) }
      let(:comment_class) do
        Struct.new(:valid, keyword_init: true) do
          def valid?
            valid
          end
        end
      end

      it 'resolves the nested predicate' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { post: { comments: [comment] } },
          errors: []
        )
      end
    end

    context 'with single-key predicate' do
      let(:predicate) { :editor }
      let(:context) { { editor: true } }

      it 'coerces predicate into a path' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { editor: true },
          errors: []
        )
      end
    end

    context 'when context key is missing' do
      let(:predicate) { :editor }
      let(:code) { :editor_required }
      let(:context) { {} }

      it 'treats missing values as falsey' do
        expect(result).to be_failure & have_attributes(
          params: [params],
          context: {},
          errors: [have_attributes(code: :editor_required, path: [:editor])]
        )
      end
    end

    context 'with expanded path references' do
      let(:predicate) { %i[comments valid?] }
      let(:context) { { comments: [valid_comment, invalid_comment] } }
      let(:valid_comment) { comment_class.new(valid: true) }
      let(:invalid_comment) { comment_class.new(valid: false) }
      let(:comment_class) do
        Struct.new(:valid, keyword_init: true) do
          def valid?
            valid
          end
        end
      end

      it 'fails every falsey reference' do
        expect(result).to be_failure & have_attributes(
          params: [params],
          context: { comments: [valid_comment, invalid_comment] },
          errors: [have_attributes(code: :not_published, path: [:comments, 1, :valid?])]
        )
      end
    end

    context 'with empty expanded path references' do
      let(:predicate) { %i[comments valid?] }
      let(:context) { { comments: [] } }

      it 'succeeds vacuously' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { comments: [] },
          errors: []
        )
      end
    end

    context 'with custom path' do
      let(:predicate) { :editor }
      let(:context) { { editor: false, predicate_result: true } }
      let(:options) { { path: custom_path } }
      let(:custom_path) { ->(root, path) { [OmniService::Path::Reference.new(path:, value: root[:predicate_result], resolved: true)] } }

      it 'uses the injected path' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { editor: false, predicate_result: true },
          errors: []
        )
      end
    end
  end

  describe '#signature' do
    subject(:signature) { assert_component.signature }

    it 'consumes only context' do
      expect(signature).to eq([0, true])
    end
  end
end
