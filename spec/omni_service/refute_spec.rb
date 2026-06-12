# frozen_string_literal: true

RSpec.describe OmniService::Refute do
  subject(:refute_component) { described_class.new(predicate, code:, **options) }

  let(:predicate) { %i[post archived?] }
  let(:code) { :already_archived }
  let(:options) { {} }

  describe '#call' do
    subject(:result) { refute_component.call(params, **context) }

    let(:params) { { title: 'Hello' } }
    let(:context) { { post: } }
    let(:post) { post_class.new(archived: archived) }
    let(:archived) { false }
    let(:post_class) do
      Struct.new(:archived, keyword_init: true) do
        def archived?
          archived
        end
      end
    end

    context 'when predicate resolves falsey' do
      it 'returns success preserving input' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { post: },
          errors: []
        )
      end
    end

    context 'when predicate resolves truthy' do
      let(:archived) { true }

      it 'returns failure with configured code' do
        expect(result).to be_failure & have_attributes(
          params: [params],
          context: { post: },
          errors: [have_attributes(code: :already_archived, path: %i[post archived?])]
        )
      end
    end

    context 'with nested hash and array path' do
      let(:predicate) { [:post, :comments, 0, :spam?] }
      let(:code) { :first_comment_spam }
      let(:context) { { post: { comments: [comment] } } }
      let(:comment) { comment_class.new(spam: true) }
      let(:comment_class) do
        Struct.new(:spam, keyword_init: true) do
          def spam?
            spam
          end
        end
      end

      it 'resolves the nested predicate' do
        expect(result).to be_failure & have_attributes(
          params: [params],
          context: { post: { comments: [comment] } },
          errors: [have_attributes(code: :first_comment_spam, path: [:post, :comments, 0, :spam?])]
        )
      end
    end

    context 'with single-key predicate' do
      let(:predicate) { :draft }
      let(:context) { { draft: false } }

      it 'coerces predicate into a path' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { draft: false },
          errors: []
        )
      end
    end

    context 'when context key is missing' do
      let(:predicate) { :draft }
      let(:context) { {} }

      it 'treats missing values as falsey' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: {},
          errors: []
        )
      end
    end

    context 'with expanded path references' do
      let(:predicate) { %i[comments spam?] }
      let(:context) { { comments: [clean_comment, first_spam_comment, second_spam_comment] } }
      let(:clean_comment) { comment_class.new(spam: false) }
      let(:first_spam_comment) { comment_class.new(spam: true) }
      let(:second_spam_comment) { comment_class.new(spam: true) }
      let(:comment_class) do
        Struct.new(:spam, keyword_init: true) do
          def spam?
            spam
          end
        end
      end

      it 'fails every truthy reference' do
        expect(result).to be_failure & have_attributes(
          params: [params],
          context: { comments: [clean_comment, first_spam_comment, second_spam_comment] },
          errors: [
            have_attributes(code: :already_archived, path: [:comments, 1, :spam?]),
            have_attributes(code: :already_archived, path: [:comments, 2, :spam?])
          ]
        )
      end
    end

    context 'with custom path' do
      let(:predicate) { :draft }
      let(:context) { { draft: true, predicate_result: false } }
      let(:options) { { path: custom_path } }
      let(:custom_path) { ->(root, path) { [OmniService::Path::Reference.new(path:, value: root[:predicate_result], resolved: true)] } }

      it 'uses the injected path' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { draft: true, predicate_result: false },
          errors: []
        )
      end
    end
  end

  describe '#signature' do
    subject(:signature) { refute_component.signature }

    it 'consumes only context' do
      expect(signature).to eq([0, true])
    end
  end
end
