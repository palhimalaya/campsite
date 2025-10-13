# frozen_string_literal: true

module Api
  module V1
    module Projects
      class PostsController < BaseController
        extend Apigen::Controller

        after_action :verify_policy_scoped, only: :index

        response model: PostPageSerializer, code: 200
        request_params do
          {
            after: { type: :string, required: false },
            limit: { type: :number, required: false },
            q: { type: :string, required: false },
            hide_resolved: { type: :boolean, required: false },
            **order_schema(by: ["last_activity_at", "published_at"]),
          }
        end
        def index
          Rails.logger.info "[PostsController#index] Starting - Project: #{params[:project_id]}, Query: #{params[:q].inspect}"
          
          authorize(current_project, :list_posts?)
          Rails.logger.info "[PostsController#index] Authorization passed"

          if params[:q].present?
            Rails.logger.info "[PostsController#index] Search query present: #{params[:q]}"
            results = Post.scoped_search(query: params[:q], organization: current_organization, project_public_id: params[:project_id])
            ids = results&.pluck(:id) || []
            Rails.logger.info "[PostsController#index] Search found #{ids.length} posts"

            posts = policy_scope(Post.in_order_of(:id, ids).feed_includes)
            Rails.logger.info "[PostsController#index] After policy_scope and feed_includes: #{posts.count} posts"
            
            render_json(
              PostPageSerializer,
              { results: posts },
            )
          else
            Rails.logger.info "[PostsController#index] Listing posts (no search)"
            scope = current_project.kept_published_posts.leaves.feed_includes
            Rails.logger.info "[PostsController#index] Base scope loaded: #{scope.count} posts"
            
            scope = scope.unresolved if to_bool(params[:hide_resolved])
            Rails.logger.info "[PostsController#index] After hide_resolved filter: #{scope.count} posts"
            
            scoped_posts = policy_scope(scope)
            Rails.logger.info "[PostsController#index] After policy_scope: #{scoped_posts.count} posts"

            Rails.logger.info "[PostsController#index] About to render_page"
            render_page(
              PostPageSerializer,
              scoped_posts,
              order: order_params(default: { published_at: :desc, id: :desc }),
            )
            Rails.logger.info "[PostsController#index] render_page completed"
          end
        rescue StandardError => e
          Rails.logger.error "[PostsController#index] ERROR: #{e.class}: #{e.message}"
          Rails.logger.error e.backtrace.first(10).join("\n")
          raise
        end

        private

        def current_project
          @current_project ||= current_organization.projects.find_by!(public_id: params[:project_id])
        end
      end
    end
  end
end
