require "rails_helper"

RSpec.describe "Api::V1::Articles", type: :request do
  describe "GET /api/v1/articles" do
    subject { get(api_v1_articles_path) }

    let!(:article1) { create(:article, :published, updated_at: 1.days.ago) }
    let!(:article2) { create(:article, :published, updated_at: 2.days.ago) }
    let!(:article3) { create(:article, :published) }

    before { create(:article, :draft) }

    # rubocop:disable RSpec/MultipleExpectations
    it "公開済みの記事の一覧が取得できる(更新順)" do
      # rubocop:enable RSpec/MultipleExpectations

      subject
      res = JSON.parse(response.body)
      expect(res.map {|d| d["id"] }).to eq [article3.id, article1.id, article2.id]
      expect(res[0].keys).to eq ["id", "title", "updated_at", "user"]
    end
  end

  describe "GET /api/v1/articles/:id" do
    subject { get(api_v1_article_path(article_id)) }

    context "指定した id の記事が存在して" do
      let(:article_id) { article.id }

      context "対象の記事が公開中であるとき" do
        let(:article) { create(:article, :published) }

        # rubocop:disable RSpec/MultipleExpectations
        it "任意の記事が取得できる" do
          # rubocop:enable RSpec/MultipleExpectations

          subject
          res = JSON.parse(response.body)
          expect(res["updated_at"]).to be_present
          expect(res["user"]["id"]).to eq article.user.id
          expect(res["user"].keys).to eq ["id", "name", "email"]
        end
      end

      context "対象の記事が下書き状態であるとき" do
        let(:article) { create(:article, :draft) }

        it "記事が見つからない" do
          expect { subject }.to raise_error ActiveRecord::RecordNotFound
        end
      end
    end

    context "指定した idの記事 が存在しないとき" do
      let(:article_id) { 77777 }

      it "その記事が見つからない" do
        expect { subject }.to raise_error ActiveRecord::RecordNotFound
      end
    end
  end

  describe "POST /api/v1/articles" do
    subject { post(api_v1_articles_path, params: params, headers: headers) }

    let(:current_user) { create(:user) }
    let(:headers) { current_user.create_new_auth_token }

    context "ログインユーザーが記事を作成するとき" do
      let(:params) { { article: attributes_for(:article) } }

      # rubocop:disable RSpec/MultipleExpectations
      it "ユーザーのレコードが作成できる" do
        # rubocop:enable RSpec/MultipleExpectations

        expect { subject }.to change { Article.where(user_id: current_user.id).count }.by(1)
        res = JSON.parse(response.body)
        expect(res["title"]).to eq params[:article][:title]
        expect(res["body"]).to eq params[:article][:body]
        expect(response).to have_http_status(:ok)
      end
    end

    context "公開 を指定して 記事を作成 するとき" do
      let(:params) { { article: attributes_for(:article, :published) } }

      # rubocop:disable RSpec/MultipleExpectations
      it "記事のレコードが作成できる" do
        # rubocop:enable RSpec/MultipleExpectations

        expect { subject }.to change { Article.where(user_id: current_user.id).count }.by(1)
        res = JSON.parse(response.body)
        expect(res["title"]).to eq params[:article][:title]
        expect(res["body"]).to eq params[:article][:body]
        expect(response).to have_http_status(:ok)
      end
    end

    context "下書き を指定して 記事を作成 するとき" do
      let(:params) { { article: attributes_for(:article, :draft) } }

      # rubocop:disable RSpec/MultipleExpectations
      it "下書き記事 が作成できる" do
        # rubocop:enable RSpec/MultipleExpectations

        expect { subject }.to change { Article.count }.by(1)
        res = JSON.parse(response.body)
        expect(res["status"]).to eq "draft"
        expect(response).to have_http_status(:ok)
      end
    end

    context "でたらめな指定で記事を作成するとき" do
      let(:params) { { article: attributes_for(:article, status: :foo) } }

      it "エラーになる" do
        expect { subject }.to raise_error(ArgumentError)
      end
    end
  end

  describe "PATCH /api/v1/articles/:id" do
    subject { patch(api_v1_article_path(article.id), params: params, headers: headers) }

    let(:params) { { article: attributes_for(:article, :published) } }
    let(:current_user) { create(:user) }
    let(:headers) { current_user.create_new_auth_token }

    context "自分の記事を更新するとき" do
      let(:article) { create(:article, :draft, user: current_user) }

      # rubocop:disable RSpec/MultipleExpectations
      it "任意の記事の更新ができる" do
        # rubocop:enable RSpec/MultipleExpectations

        expect { subject }.to change { article.reload.title }.from(article.title).to(params[:article][:title]) &
                              change { article.reload.body }.from(article.body).to(params[:article][:body]) &
                              change { article.reload.status }.from(article.status).to(params[:article][:status].to_s)
        expect(response).to have_http_status(:ok)
      end
    end

    context "他のユーザーの記事を更新しようとするとき" do
      let(:other_user) { create(:user) }
      let!(:article) { create(:article, user: other_user) }

      it "更新できない" do
        expect { subject }.to raise_error(ActiveRecord::RecordNotFound)
        change { Article.count }.by(0)
      end
    end
  end

  describe "DELETE /api/v1/articles/:id" do
    subject { delete(api_v1_article_path(article_id), headers: headers) }

    let(:current_user) { create(:user) }
    let(:article_id) { article.id }
    let(:headers) { current_user.create_new_auth_token }

    context "自分の記事を削除しようとするとき" do
      let!(:article) { create(:article, user: current_user) }

      # rubocop:disable RSpec/MultipleExpectations
      it "記事を削除できる" do
        # rubocop:enable RSpec/MultipleExpectations

        expect { subject }.to change { Article.count }.by(-1)
        expect(response).to have_http_status(:ok)
      end
    end

    context "他人が所持している記事のレコードを削除しようとするとき" do
      let(:other_user) { create(:user) }
      let!(:article) { create(:article, user: other_user) }

      it "記事を削除できない" do
        expect { subject }.to raise_error(ActiveRecord::RecordNotFound) &
                              change { Article.count }.by(0)
      end
    end
  end
end
