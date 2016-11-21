module Pageflow
  ActiveAdmin.register Pageflow.config.user_class.constantize do
    menu :priority => 2

    config.batch_actions = false
    config.clear_action_items!

    index do
      column :full_name, :sortable => 'last_name' do |user|
        link_to(user.full_name, send("admin_#{Pageflow.config.user_class.underscore}_path", user))
      end
      column :email
      if authorized?(:read, Account)
        column :account, :sortable => 'account_id' do |user|
          if user.account && admin_account_path(user.account)
            link_to(user.account.try(:name), admin_account_path(user.account))
          else
            user.account.try(:name).present? ? user.account.name : 'Unknown'
          end

        end
      end
      column :role, :sortable => 'role' do |user|
        I18n.t(user.role, :scope => 'pageflow.admin.users.roles')
      end
      column :last_sign_in_at
      column :sign_in_count
      boolean_status_tag_column :suspended?
    end

    filter :last_name
    filter :first_name
    filter :email

    # FIXME: this method is currently not finding the current_pageflow_user, commenting out for now as we don't really need it
    # action_item(:invite, only: :index) do
    #   link_to I18n.t('pageflow.admin.users.invite_user'), send("new_admin_#{Pageflow.config.user_class.underscore}_path", current_pageflow_user), :data => {:rel => 'invite_user'}
    # end

    show do |user|
      div :class => :columns do
        div do
          attributes_table_for user do
            row :last_name, :class => 'last_name'
            row :first_name, :class => 'first_name'
            row :email, :class => 'email'
            if authorized?(:read, Account)
              row :account, :class => 'account'
            end
            row :role, :class => 'role' do
              span 'data-user-role' => user.role do
                I18n.t(user.role, :scope => 'pageflow.admin.users.roles')
              end
            end

            row :created_at
            row :last_sign_in_at
            boolean_status_tag_row :suspended?
            row :locale do
              I18n.t('language', locale: user.locale)
            end
          end

          para do
            link_to I18n.t('pageflow.admin.users.resend_invitation'), send("resend_invitation_admin_#{Pageflow.config.user_class.underscore}_path", user), :method => :post, :class => 'button', :data => {:rel => 'resend_invitation'}
          end
        end

        panel I18n.t('activerecord.models.entry.other') do
          embedded_index_table(user.memberships.includes(:entry).references(:pageflow_entry),
                               blank_slate_text: I18n.t('pageflow.admin.users.empty')) do
            table_for_collection sortable: true, class: 'memberships', i18n: Membership do
              column :entry, sortable: 'pageflow_entries.title' do |membership|
                link_to(membership.entry.title, admin_entry_path(membership.entry))
              end
              column :created_at, sortable: 'pageflow_memberships.created_at'
              column do |membership|
                if authorized?(:destroy, membership)
                  link_to(I18n.t('pageflow.admin.users.delete'),
                          send("admin_#{Pageflow.config.user_class.underscore}_membership_path", user, membership),
                          method: :delete,
                          data: {
                            confirm: I18n.t('active_admin.delete_confirmation'),
                            rel: 'delete_membership'
                          })
                end
              end
            end
          end

          span do
            link_to(I18n.t('pageflow.admin.users.add_entry'),
                    send("new_admin_#{Pageflow.config.user_class.underscore}_membership_path", user),
                    class: 'button',
                    data: {
                      rel: 'add_membership'
                    })
          end
        end
      end
    end

    action_item(:edit, only: :show) do
      link_to I18n.t('pageflow.admin.users.edit'), send("edit_admin_#{Pageflow.config.user_class.underscore}_path", resource), :data => {:rel => 'edit_user'}
    end

    action_item(:toggle_suspended, only: :show) do
      if resource != current_user
        if resource.suspended?
          link_to I18n.t('pageflow.admin.users.unsuspend'), send("unsuspend_admin_#{Pageflow.config.user_class.underscore}_path", resource), :method => :post, :data => {:rel => 'unsuspend_user'}
        else
          link_to I18n.t('pageflow.admin.users.suspend'), send("suspend_admin_#{Pageflow.config.user_class.underscore}_path", resource), :method => :post, :data => {:rel => 'suspend_user'}
        end
      end
    end

    action_item(:delete, only: :show) do
      if resource != current_user
        link_to I18n.t('pageflow.admin.users.delete'), send("admin_#{Pageflow.config.user_class.underscore}_path", resource), :method => :delete, :data => {:rel => 'delete_user', :confirm => I18n.t('pageflow.admin.users.confirm_delete')}
      end
    end

    form(:partial => 'form')

    collection_action 'me', :title => I18n.t('pageflow.admin.users.account'), :method => [:get, :patch] do
      if request.patch?
        if current_user.update_with_password(user_profile_params)
          sign_in current_pageflow_user, :bypass => true
          redirect_to admin_root_path, :notice => I18n.t('pageflow.admin.users.me.updated')
        end
      end
    end

    collection_action 'delete_me', :title => I18n.t('pageflow.admin.users.account'), :method => [:get, :delete] do
      if request.delete?
        if authorized?(:delete_own_user, current_pageflow_user) &&
           current_user.destroy_with_password(params.require(:user)[:current_password])
          redirect_to admin_root_path, :notice => I18n.t('pageflow.admin.users.me.updated')
        end
      end
    end

    member_action :resend_invitation, :method => :post do
      InvitedUser.find(params[:id]).send_invitation!
      redirect_to :back, :notice => I18n.t('pageflow.admin.users.resent_invitation')
    end

    member_action :suspend, :method => :post do
      User.find(params[:id]).suspend!
      redirect_to :back, :notice => I18n.t('pageflow.admin.users.suspended')
    end

    member_action :unsuspend, :method => :post do
      User.find(params[:id]).unsuspend!
      redirect_to :back, :notice => I18n.t('pageflow.admin.users.unsuspended')
    end

    controller do
      include Pageflow::QuotaVerification

      helper Pageflow::Admin::UsersHelper
      helper Pageflow::Admin::LocalesHelper
      helper Pageflow::Admin::FormHelper
      helper Pageflow::QuotaHelper

      def build_new_resource
        user = InvitedUser.new(permitted_params[:user])
        user.account ||= current_pageflow_user.account
        user
      end

      def create_resource(user)
        verify_quota!(:users, resource.account)
        super
      end

      def user_profile_params
        params.require(:user).permit(:first_name, :last_name, :current_password, :password, :password_confirmation, :locale)
      end

      def permitted_params
        result = params.permit(:user => [:first_name, :last_name, :email, :password, :password_confirmation, :account_id, :role, :locale])
        restrict_attributes(params[:id], result[:user]) if result[:user]
        result
      end

      private

      def restrict_attributes(id, attributes)
        if !authorized?(:read, Account)
          attributes.delete(:account_id)
        end

        if !authorized?(:read, Account) && !User::NON_ADMIN_ROLES.include?(attributes[:role])
          attributes.delete(:role)
        end
      end
    end
  end
end
